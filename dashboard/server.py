"""The web dashboard, and the status screen on the laptop's own display.

Runs as the agent account on 127.0.0.1:7380 (see modules/dashboard.nix).
`tailscale serve` puts it on the tailnet and adds the Tailscale-User-Login
header to every request; the dashboard only answers logins that own this
machine or are listed in `dashboardUsers` in settings.nix.

/screen, its files and /api/screen need no login. They are what the laptop's
own display shows (modules/screen.nix) and hold nothing secret.

/terminal is the web terminal (ttyd on 127.0.0.1:7381). It goes through this
server too, so it has the same login check.

Changes go through the `agency` command, as jobs that run outside this
service (systemd-run --user), so a rebuild that restarts the dashboard does
not stop the rebuild. One job runs at a time.

Python standard library only.
"""

import html
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PORT = int(os.environ.get("AGENCY_DASHBOARD_PORT", "7380"))
UI = Path(os.environ.get("AGENCY_UI", Path(__file__).parent / "ui"))
FONTS = Path(os.environ.get("AGENCY_FONTS", Path(__file__).parent.parent / "installer/ui/fonts"))
USER = os.environ.get("AGENCY_USER", "agent")
EXTRA_LOGINS = {u.strip().lower() for u in os.environ.get("AGENCY_DASHBOARD_USERS", "").split() if u.strip()}
TERMINAL = ("127.0.0.1", int(os.environ.get("AGENCY_TERMINAL_PORT", "7381")))
# Overridable so the server can be tried off the real machine.
REPO = Path(os.environ.get("AGENCY_REPO", "/etc/nixos"))
URL_FILE = Path(os.environ.get("AGENCY_URL_FILE", "/run/agency/dashboard-url"))
PROFILE = Path(os.environ.get("AGENCY_PROFILE", "/nix/var/nix/profiles/system"))
RECOVERY_KEY = "/root/luks-recovery-key.txt"
HOME = Path.home()

LOGIN_HEADER = "Tailscale-User-Login"
SECRET_NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")
APP_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def sh(*cmd, timeout=30, env=None, stdin=None):
    """Run a command; return (ok, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           env=env, input=stdin, errors="replace")
        return p.returncode == 0, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, "", str(e)


def cached(ttl):
    """Remember a function's result for ttl seconds."""
    def wrap(fn):
        memo = {}
        lock = threading.Lock()

        def inner(*args):
            with lock:
                hit = memo.get(args)
                if hit and time.time() - hit[0] < ttl:
                    return hit[1]
            value = fn(*args)
            with lock:
                memo[args] = (time.time(), value)
            return value

        inner.clear = memo.clear
        return inner
    return wrap


def which(name):
    """Find a program, including the agent's npm and pip installs."""
    extra = [str(HOME / ".npm-global/bin"), str(HOME / ".local/bin")]
    return shutil.which(name, path=os.pathsep.join([os.environ.get("PATH", "")] + extra))


# ------------------------------------------------------------------ facts ---


@cached(20)
def tailscale_status():
    ok, out, _ = sh("tailscale", "status", "--json", timeout=10)
    try:
        return json.loads(out) if ok else {}
    except ValueError:
        return {}


def owner_login():
    """The login of the person whose tailnet this machine is on."""
    st = tailscale_status()
    user = (st.get("User") or {}).get(str((st.get("Self") or {}).get("UserID", "")))
    return (user or {}).get("LoginName", "").lower()


def tailnet_name():
    st = tailscale_status()
    if st.get("BackendState") != "Running":
        return ""
    return ((st.get("Self") or {}).get("DNSName") or "").rstrip(".")


def read_setting(key):
    try:
        match = re.search(rf"^  {key} = (.*);$", (REPO / "settings.nix").read_text(), re.M)
    except OSError:
        return None
    return match.group(1) if match else None


def desktop_count():
    value = read_setting("desktops")
    return int(value) if value and value.isdigit() else 1


def unit_state(unit):
    _, out, _ = sh("systemctl", "is-active", unit, timeout=5)
    return out.strip() or "unknown"


def machine_state():
    _, out, _ = sh("systemctl", "is-system-running", timeout=5)
    return out.strip() or "unknown"


def windows(n):
    ok, out, _ = sh("wmctrl", "-l", timeout=5, env=dict(os.environ, DISPLAY=f":{n}"))
    return len(out.splitlines()) if ok else None


def desktops():
    found = []
    for n in range(1, desktop_count() + 1):
        state = unit_state(f"agency-display@{n}.service")
        found.append({"n": n, "port": 6080 + n, "running": state == "active",
                      "windows": windows(n) if state == "active" else None})
    return found


class Shots:
    """Screenshots of the desktops, at most one every two seconds each."""

    def __init__(self):
        self.dir = Path(tempfile.mkdtemp(prefix="agency-dashboard-shots-"))
        self.locks = {}
        self.taken = {}

    def get(self, n):
        lock = self.locks.setdefault(n, threading.Lock())
        path = self.dir / f"{n}.jpg"
        with lock:
            if time.time() - self.taken.get(n, 0) > 2:
                ok, _, _ = sh("scrot", "--overwrite", "--silent", "--quality", "60", str(path),
                              timeout=10, env=dict(os.environ, DISPLAY=f":{n}"))
                self.taken[n] = time.time()
                if not ok:
                    path.unlink(missing_ok=True)
            return path.read_bytes() if path.exists() else None


shots = Shots()

# Where each agent CLI keeps its sign-in.
TOOLS = [
    ("github", "GitHub", "gh", None),
    ("claude", "Claude Code", "claude", ".claude/.credentials.json"),
    ("codex", "Codex", "codex", ".codex/auth.json"),
    ("opencode", "OpenCode", "opencode", ".local/share/opencode/auth.json"),
]


@cached(30)
def accounts():
    found = []
    for tool_id, label, program, auth_file in TOOLS:
        entry = {"id": tool_id, "label": label, "installed": bool(which(program)), "signedIn": False, "detail": ""}
        if tool_id == "github" and entry["installed"]:
            ok, out, err = sh("gh", "auth", "status", "--hostname", "github.com", timeout=15)
            entry["signedIn"] = ok
            name = re.search(r"(?:account|as) (\S+)", out + err) if ok else None
            entry["detail"] = f"Signed in as {name.group(1)}" if name else ("Signed in" if ok else "Not signed in")
        elif entry["installed"]:
            entry["signedIn"] = (HOME / auth_file).exists()
            entry["detail"] = "Signed in" if entry["signedIn"] else "Not signed in"
        else:
            continue  # only tools that are installed; add others under Apps
        found.append(entry)
    return found


@cached(600)
def apps():
    ok, out, err = sh("agency", "apps", timeout=180)
    if not ok:
        last = (err or out).strip().splitlines()
        return {"apps": [], "error": last[-1] if last else "agency apps failed"}
    found = []
    for line in out.splitlines():
        m = re.match(r"^ ([* ]) (\S+)\s+(.*)$", line)
        if m and APP_ID.match(m.group(2)):
            found.append({"id": m.group(2), "label": m.group(3).strip(), "on": m.group(1) == "*"})
    return {"apps": found, "error": ""}


def secrets():
    ok, out, _ = sh("agency", "secret", "list", timeout=30)
    return [line.strip() for line in out.splitlines() if SECRET_NAME.match(line.strip())] if ok else []


def generation():
    """The running system's generation number and when it was made."""
    try:
        link = os.readlink(PROFILE)
    except OSError:
        return None, None
    m = re.search(r"system-(\d+)-link", link)
    target = PROFILE.parent / link if not os.path.isabs(link) else Path(link)
    try:
        made = os.lstat(target).st_mtime
    except OSError:
        made = None
    return (int(m.group(1)) if m else None), made


def memory():
    try:
        info = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
        total = int(info["MemTotal"].split()[0]) * 1024
        available = int(info["MemAvailable"].split()[0]) * 1024
        return {"used": total - available, "total": total}
    except (OSError, KeyError, ValueError):
        return None


@cached(30)
def recovery_key_present():
    ok, _, _ = sh("sudo", "-n", "test", "-e", RECOVERY_KEY, timeout=10)
    return ok


def system():
    gen, made = generation()
    disk = shutil.disk_usage("/")
    return {
        "generation": gen,
        "generationTime": made,
        "disk": {"used": disk.used, "total": disk.total},
        "memory": memory(),
        "recoveryKey": recovery_key_present(),
    }


# ---------------------------------------------------------------- updates ---


class Updates:
    """Whether the repo has new commits. Fetched every six hours, or on request."""

    def __init__(self):
        self.lock = threading.Lock()
        self.state = {"linked": (REPO / ".git").is_dir(), "behind": 0, "subjects": [],
                      "repo": "", "checked": None, "error": ""}

    def check(self, fetch=True):
        linked = (REPO / ".git").is_dir()
        state = {"linked": linked, "behind": 0, "subjects": [], "repo": "", "checked": time.time(), "error": ""}
        if linked:
            _, url, _ = sh("git", "-C", str(REPO), "remote", "get-url", "origin", timeout=10)
            state["repo"] = re.sub(r"^https://github\.com/|\.git$", "", url.strip())
            if fetch:
                ok, _, err = sh("git", "-C", str(REPO), "fetch", "-q", "origin", timeout=90)
                if not ok:
                    state["error"] = "Could not reach the repo to check for updates."
            ok, out, _ = sh("git", "-C", str(REPO), "log", "--format=%s", "HEAD..@{u}", timeout=10)
            subjects = out.splitlines() if ok else []
            state.update(behind=len(subjects), subjects=subjects[:5])
        with self.lock:
            self.state = state
        return state

    def loop(self):
        time.sleep(60)
        while True:
            self.check()
            time.sleep(6 * 3600)


updates = Updates()


# ------------------------------------------------------------------- jobs ---
# A job is one `agency` command. It runs in its own transient user unit, so
# it keeps going if this server restarts. Its log, exit status and a note of
# what it is live in STATE, which survives the restart too.

# systemd-run --user and systemctl --user find the agent's user manager here.
if not os.environ.get("XDG_RUNTIME_DIR") and Path(f"/run/user/{os.getuid()}").is_dir():
    os.environ["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"

STATE = Path(os.environ.get("AGENCY_DASHBOARD_STATE")
             or Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "agency-dashboard")

# Runs the command with stdin from a file (deleted once open), then writes
# the exit status where the server looks for it.
WRAPPER = ('st="$1"; in="$2"; shift 2; '
           'if [ -n "$in" ]; then exec 3<"$in"; rm -f "$in"; else exec 3</dev/null; fi; '
           '"$@" <&3 3<&-; echo $? > "$st"')


class Jobs:
    def __init__(self):
        self.lock = threading.Lock()
        self.proc = None
        self.use_systemd = bool(shutil.which("systemd-run")) and not os.environ.get("AGENCY_JOBS_DIRECT")
        self.finished_seen = None

    def current(self):
        try:
            return json.loads((STATE / "job.json").read_text())
        except (OSError, ValueError):
            return None

    def status(self):
        job = self.current()
        if not job:
            return None
        log_file = STATE / f"{job['id']}.log"
        status_file = STATE / f"{job['id']}.status"
        try:
            log = log_file.read_text(errors="replace").splitlines()[-400:]
        except OSError:
            log = []
        state, code = "running", None
        if status_file.exists():
            text = status_file.read_text().strip()
            code = int(text) if text.lstrip("-").isdigit() else 1
            state = "done" if code == 0 else "failed"
        elif time.time() - job["started"] > 5 and not self.alive(job):
            state, code = "failed", None
        return {**job, "state": state, "code": code, "log": log}

    def alive(self, job):
        if self.use_systemd:
            _, out, _ = sh("systemctl", "--user", "is-active", job["unit"], timeout=5)
            return out.strip() in ("active", "activating", "reloading")
        return self.proc is not None and self.proc.poll() is None

    def running(self):
        st = self.status()
        return bool(st and st["state"] == "running")

    def start(self, kind, title, cmd, stdin=None):
        with self.lock:
            if self.running():
                return {"ok": False, "error": "Another change is still running. Wait for it to finish."}
            STATE.mkdir(parents=True, exist_ok=True)
            os.chmod(STATE, 0o700)
            job_id = time.strftime("%Y%m%d-%H%M%S-") + f"{int(time.time() * 1000) % 1000:03d}"
            log, status = STATE / f"{job_id}.log", STATE / f"{job_id}.status"
            infile = ""
            unit = f"agency-dashboard-job-{job_id}"
            argv = [shutil.which("sh") or "/bin/sh", "-c", WRAPPER, "sh", str(status), "", *cmd]
            try:
                if stdin is not None:
                    infile = argv[5] = str(STATE / f"{job_id}.in")
                    fd = os.open(infile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    with os.fdopen(fd, "w") as f:
                        f.write(stdin)
                log.write_text("")
                if self.use_systemd:
                    path = os.pathsep.join(["/run/wrappers/bin", os.environ.get("PATH", "")])
                    ok, _, err = sh("systemd-run", "--user", "--quiet", "--collect", f"--unit={unit}",
                                    f"--description=agency dashboard: {title}",
                                    f"--setenv=PATH={path}",
                                    f"--property=StandardOutput=append:{log}",
                                    f"--property=StandardError=append:{log}",
                                    "--", *argv, timeout=20)
                    if not ok:
                        # No user manager to run it in: run it here instead.
                        print(f"systemd-run failed, running the job directly: {err.strip()}", file=sys.stderr)
                        self.use_systemd = False
                if not self.use_systemd:
                    with open(log, "ab") as out:
                        self.proc = subprocess.Popen(argv, stdout=out, stderr=subprocess.STDOUT,
                                                     stdin=subprocess.DEVNULL, start_new_session=True)
            except OSError as e:
                if infile:
                    Path(infile).unlink(missing_ok=True)
                return {"ok": False, "error": f"Could not start it: {e}"}
            for old in STATE.glob("*"):
                if old.name.split(".")[0] not in (job_id, "job"):
                    old.unlink(missing_ok=True)
            (STATE / "job.json").write_text(json.dumps(
                {"id": job_id, "kind": kind, "title": title, "unit": unit, "started": time.time()}))
            return {"ok": True}

    def dismiss(self):
        with self.lock:
            if not self.running():
                (STATE / "job.json").unlink(missing_ok=True)

    def after_finish(self, st):
        """Refresh what a finished job may have changed, once per job."""
        if st and st["state"] != "running" and self.finished_seen != st["id"]:
            self.finished_seen = st["id"]
            apps.clear()
            accounts.clear()
            threading.Thread(target=updates.check, args=(False,), daemon=True).start()


jobs = Jobs()


# ----------------------------------------------------------------- screen ---


def qr_svg(text):
    ok, out, _ = sh("qrencode", "-t", "SVG", "-m", "0", "--foreground=101813", "--background=eef5e6",
                    "-o", "-", text, timeout=10)
    return out[out.find("<svg"):] if ok and "<svg" in out else ""


qr_cached = cached(3600)(qr_svg)


def when(stamp):
    if not stamp:
        return ""
    then, now = datetime.fromtimestamp(stamp), datetime.now()
    days = (now.date() - then.date()).days
    if days == 0:
        return "today"
    if days == 1:
        return "yesterday"
    return then.strftime("on %-d %b" if then.year == now.year else "on %-d %b %Y")


def joined(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


@cached(60)
def console_password():
    """Whether the agent account has a password, so the console can be used."""
    ok, out, _ = sh("sudo", "-n", "passwd", "-S", USER, timeout=10)
    return ok and len(out.split()) > 1 and out.split()[1] == "P"


def screen():
    name = tailnet_name()
    try:
        url = URL_FILE.read_text().strip()
    except OSError:
        url = ""
    _, made = generation()
    up = updates.state
    updated = f"updated {when(made)}" if made else ""
    if up["checked"] and up["linked"] and not up["error"] and up["behind"] == 0:
        text = "Up to date" + (f", {updated}" if updated else "")
    elif up["behind"]:
        text = f"{up['behind']} update{'s' if up['behind'] != 1 else ''} ready" + (f", {updated}" if updated else "")
    else:
        text = updated.capitalize() or "Unknown"
    state = machine_state()
    return {
        "hostname": socket.gethostname().split(".")[0],
        "state": "Starting" if state in ("starting", "initializing") else "Running",
        "tailscale": name,
        "desktops": joined([f":{n}" for n in range(1, desktop_count() + 1)]),
        "system": text,
        "url": url if name else "",
        "qr": qr_cached(url) if name and url else "",
        "console": console_password(),
    }



# ------------------------------------------------------------ GitHub ---
# Sign in with GitHub's device flow, the same one `gh auth login` uses: the
# page shows a short code, you enter it at github.com/login/device on any
# device, and the token goes to `gh auth login --with-token`. No terminal.

GH_CLIENT_ID = "178c6fc778ccc68e1d6a"  # the GitHub CLI's own OAuth app
GH_SCOPES = "repo read:org gist workflow"


def github_post(url, fields):
    from urllib.parse import urlencode
    from urllib.request import Request, urlopen
    req = Request(url, data=urlencode(fields).encode(), headers={"Accept": "application/json"})
    with urlopen(req, timeout=20) as r:
        return json.loads(r.read())


class GitHubLogin:
    def __init__(self):
        self.lock = threading.Lock()
        self.state = {"state": "idle", "code": "", "url": "", "error": ""}
        self.run_id = 0

    def start(self):
        with self.lock:
            if self.state["state"] == "waiting":
                return self.state
            self.run_id += 1
            self.state = {"state": "starting", "code": "", "url": "", "error": ""}
            run_id = self.run_id
        threading.Thread(target=self._run, args=(run_id,), daemon=True).start()
        return self.state

    def cancel(self):
        with self.lock:
            self.run_id += 1
            self.state = {"state": "idle", "code": "", "url": "", "error": ""}
        return self.state

    def _set(self, run_id, **kw):
        with self.lock:
            if run_id == self.run_id:
                self.state.update(kw)
            return run_id == self.run_id

    def _run(self, run_id):
        try:
            dev = github_post("https://github.com/login/device/code",
                              {"client_id": GH_CLIENT_ID, "scope": GH_SCOPES})
        except Exception:
            self._set(run_id, state="failed", error="Could not reach GitHub.")
            return
        self._set(run_id, state="waiting", code=dev["user_code"], url=dev["verification_uri"])
        interval = int(dev.get("interval", 5))
        deadline = time.time() + int(dev.get("expires_in", 900))
        while time.time() < deadline:
            time.sleep(interval)
            if not self._set(run_id):
                return  # cancelled
            try:
                res = github_post("https://github.com/login/oauth/access_token", {
                    "client_id": GH_CLIENT_ID, "device_code": dev["device_code"],
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
            except Exception:
                continue
            err = res.get("error")
            if err == "authorization_pending":
                continue
            if err == "slow_down":
                interval += 5
                continue
            if err:
                self._set(run_id, state="failed",
                          error="The code ran out. Try again." if err == "expired_token" else "GitHub said no.")
                return
            ok, _, _ = sh("gh", "auth", "login", "--hostname", "github.com", "--git-protocol", "https",
                          "--with-token", stdin=res["access_token"] + "\n")
            if ok:
                sh("gh", "auth", "setup-git")
            accounts.clear()
            self._set(run_id, state="done" if ok else "failed", code="",
                      error="" if ok else "gh could not save the sign-in.")
            return
        self._set(run_id, state="failed", error="The code ran out. Try again.")


github_login = GitHubLogin()

# ------------------------------------------------------------------- HTTP ---

TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
         ".js": "text/javascript; charset=utf-8", ".woff2": "font/woff2"}
OPEN_FILES = {"/screen": "screen.html", "/screen.css": "screen.css", "/screen.js": "screen.js"}
FILES = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}
SHOT = re.compile(r"^/api/desktops/(\d+)/shot$")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    # --- replies

    def send(self, status, body, ctype, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_json(self, data, status=200):
        self.send(status, json.dumps(data).encode(), "application/json")

    def send_file(self, path):
        try:
            data = path.read_bytes()
        except OSError:
            return self.send_json({"error": "not found"}, 404)
        self.send(200, data, TYPES.get(path.suffix, "application/octet-stream"))

    def refuse(self, why):
        page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Not allowed</title><body style="font:16px/1.5 system-ui,sans-serif;max-width:36rem;margin:3rem auto;padding:0 1rem;color:#15201a;background:#eef1ec">
<h1 style="font-size:1.5rem">Not allowed</h1><p>{html.escape(why)}</p></body>"""
        if self.path.startswith("/api/"):
            return self.send_json({"error": why}, 403)
        self.send(403, page.encode(), TYPES[".html"])

    # --- checks

    def login(self):
        """The Tailscale login allowed to use the dashboard, or None (after refusing)."""
        login = (self.headers.get(LOGIN_HEADER) or "").strip().lower()
        if not login:
            self.refuse("The dashboard only opens through Tailscale. Open this machine's "
                        "Tailscale address from a device on your tailnet.")
            return None
        if login != owner_login() and login not in EXTRA_LOGINS:
            self.refuse(f"You are signed in to Tailscale as {login}, which does not own this machine. "
                        "To let this login in, add it to dashboardUsers in settings.nix and rebuild.")
            return None
        return login

    def same_origin(self):
        origin = self.headers.get("Origin")
        if not origin:
            return True
        hosts = {self.headers.get("Host", ""), self.headers.get("X-Forwarded-Host", "")}
        return urlsplit(origin).netloc in hosts - {""}

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return {}

    # --- routes

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?")[0]
        # The laptop's own screen: no login.
        if path in OPEN_FILES:
            return self.send_file(UI / OPEN_FILES[path])
        if path.startswith("/fonts/"):
            name = path[len("/fonts/"):]
            if re.match(r"^[a-z0-9-]+\.woff2$", name):
                return self.send_file(FONTS / name)
            return self.send_json({"error": "not found"}, 404)
        if path == "/api/screen":
            return self.send_json(screen())

        login = self.login()
        if not login:
            return
        if path == "/terminal" or path.startswith("/terminal/"):
            return self.proxy_terminal()
        if path in FILES:
            return self.send_file(UI / FILES[path])
        if path == "/api/state":
            job = jobs.status()
            jobs.after_finish(job)
            return self.send_json({
                "hostname": socket.gethostname().split(".")[0],
                "login": login,
                "state": machine_state(),
                "tailscale": tailnet_name(),
                "desktops": desktops(),
                "accounts": accounts(),
                "secrets": secrets(),
                "system": system(),
                "updates": updates.state,
                "job": job,
            })
        if path == "/api/apps":
            return self.send_json(apps())
        if path == "/api/github":
            return self.send_json(github_login.state)
        if path == "/api/job":
            job = jobs.status()
            jobs.after_finish(job)
            return self.send_json({"job": job})
        shot = SHOT.match(path)
        if shot and 1 <= int(shot.group(1)) <= desktop_count():
            data = shots.get(int(shot.group(1)))
            if data is None:
                return self.send_json({"error": "no picture"}, 404)
            return self.send(200, data, "image/jpeg")
        return self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        if not self.login():
            return
        if path.startswith("/terminal"):
            return self.proxy_terminal()
        # A page on another site cannot send JSON here, or claim our origin.
        if not self.same_origin() or not (self.headers.get("Content-Type") or "").startswith("application/json"):
            return self.send_json({"error": "bad request"}, 400)
        data = self.body()

        if path == "/api/update/check":
            return self.send_json(updates.check())
        if path == "/api/github/start":
            return self.send_json(github_login.start())
        if path == "/api/github/cancel":
            return self.send_json(github_login.cancel())
        if path == "/api/job/dismiss":
            jobs.dismiss()
            return self.send_json({"ok": True})

        count = desktop_count()
        job = None
        if path == "/api/update":
            job = ("update", "Updating", ["agency", "update"])
        elif path == "/api/rollback":
            job = ("rollback", "Going back to the previous system", ["agency", "rollback"])
        elif path == "/api/desktops/add":
            job = ("desktop", f"Adding desktop :{count + 1}", ["agency", "desktop", "add"])
        elif path == "/api/desktops/remove":
            if count == 1:
                return self.send_json({"ok": False, "error": "Desktop :1 always stays."})
            job = ("desktop", f"Removing desktop :{count}", ["agency", "desktop", "remove"])
        elif path in ("/api/apps/add", "/api/apps/remove"):
            app_id = str(data.get("id", ""))
            known = {a["id"]: a for a in apps()["apps"]}
            if not APP_ID.match(app_id) or app_id not in known:
                return self.send_json({"ok": False, "error": "There is no app with that name."})
            verb = "add" if path.endswith("add") else "remove"
            label = known[app_id]["label"]
            job = ("apps", f"{'Adding' if verb == 'add' else 'Removing'} {label}", ["agency", "apps", verb, app_id])
        elif path == "/api/secrets/set":
            name, value = str(data.get("name", "")), data.get("value")
            if not SECRET_NAME.match(name):
                return self.send_json({"ok": False, "error": "Use a name like OPENAI_API_KEY: capitals, digits and _."})
            if not isinstance(value, str) or not value.strip():
                return self.send_json({"ok": False, "error": "The value is empty."})
            # The value goes to `agency secret set` on stdin, never in argv.
            return self.send_json(jobs.start("secrets", f"Saving {name}", ["agency", "secret", "set", name],
                                             stdin=value.rstrip("\n") + "\n"))
        elif path == "/api/secrets/remove":
            name = str(data.get("name", ""))
            if not SECRET_NAME.match(name):
                return self.send_json({"ok": False, "error": "There is no secret with that name."})
            job = ("secrets", f"Removing {name}", ["agency", "secret", "remove", name])
        if job is None:
            return self.send_json({"error": "not found"}, 404)
        kind, title, cmd = job
        return self.send_json(jobs.start(kind, title, cmd))

    # --- the web terminal

    def proxy_terminal(self):
        """Pass the request (and a WebSocket, if it is one) to ttyd as it is."""
        if not self.same_origin():
            return self.send_json({"error": "bad request"}, 400)
        try:
            upstream = socket.create_connection(TERMINAL, timeout=5)
        except OSError:
            return self.send(502, b"The terminal is not running. Over SSH: systemctl status agency-terminal",
                             "text/plain; charset=utf-8")
        upstream.settimeout(None)
        upgrade = (self.headers.get("Upgrade") or "").lower() == "websocket"
        lines = [f"{self.command} {self.path} HTTP/1.1"]
        for key, value in self.headers.items():
            if key.lower() == "connection" and not upgrade:
                continue
            lines.append(f"{key}: {value}")
        if not upgrade:
            lines.append("Connection: close")
        upstream.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("latin-1"))
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            upstream.sendall(self.rfile.read(length))
        self.close_connection = True

        if not upgrade:
            # Add a frame rule to ttyd's reply, so no other site can frame it.
            head = b""
            while b"\r\n\r\n" not in head:
                chunk = upstream.recv(65536)
                if not chunk:
                    break
                head += chunk
            end = head.find(b"\r\n\r\n")
            if end >= 0:
                head = head[:end] + b"\r\nX-Frame-Options: SAMEORIGIN" + head[end:]
            self.connection.sendall(head)
            while chunk := upstream.recv(65536):
                self.connection.sendall(chunk)
            upstream.close()
            return

        def downstream():
            try:
                while chunk := upstream.recv(65536):
                    self.connection.sendall(chunk)
            except OSError:
                pass
            finally:
                for s in (self.connection, upstream):
                    try:
                        s.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass

        threading.Thread(target=downstream, daemon=True).start()
        try:
            while chunk := self.rfile.read1(65536):
                upstream.sendall(chunk)
        except OSError:
            pass
        finally:
            try:
                upstream.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            upstream.close()


if __name__ == "__main__":
    threading.Thread(target=updates.loop, daemon=True).start()
    host = os.environ.get("AGENCY_DASHBOARD_HOST", "127.0.0.1")
    print(f"agency dashboard on http://{host}:{PORT}", file=sys.stderr, flush=True)
    ThreadingHTTPServer((host, PORT), Handler).serve_forever()
