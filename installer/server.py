"""Backend for the setup screen.

The setup screen is a web page (installer/ui) shown fullscreen on the machine
being installed. This small server, on localhost only, gives that page what
it needs: the network state, SSH keys, the list of disks, a Tailscale
sign-in, optional sign-ins to GitHub and the agent CLIs, and a way to start
the install and watch it.

It installs nothing itself. The install is done by agency-install, the same
script the text wizard and unattended mode use; this server runs it with the
answers collected on screen and reports its progress.

Python standard library only.
"""

import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 7373
UI = Path(os.environ["AGENCY_UI"])
HOSTNAME = os.environ.get("AGENCY_HOSTNAME") or "agency"
USER = os.environ.get("AGENCY_USER", "agent")
GITHUB_USER = os.environ.get("AGENCY_GITHUB_USER", "")
APPS_TABLE = Path(os.environ["AGENCY_APPS"])
SYSTEM = os.environ.get("AGENCY_SYSTEM", "")
INSTALLER = os.environ.get("AGENCY_INSTALLER", "agency-install")
WORK = Path(os.environ.get("AGENCY_WORK", "/tmp/agency-setup"))
# Overridable so the server can be tested off the real machine.
SYS = Path(os.environ.get("AGENCY_SYS", "/sys"))
DEV = Path(os.environ.get("AGENCY_DEV", "/dev"))
MNT = Path(os.environ.get("AGENCY_MNT", "/mnt"))

KEY_LINE = re.compile(r"^(ssh-|ecdsa-|sk-)", re.M)
USERNAME = re.compile(r"^[A-Za-z0-9-]{1,39}$")
MACHINE_NAME = re.compile(r"^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$")


def sh(*cmd, timeout=30):
    """Run a command; return (ok, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode == 0, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, "", str(e)


def qr_svg(text):
    ok, out, _ = sh("qrencode", "-t", "SVG", "-m", "2", "-o", "-", text)
    return out[out.find("<svg"):] if ok and "<svg" in out else ""


def human(size):
    size = float(size)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size:.0f} {unit}" if size >= 10 or size == int(size) else f"{size:.1f} {unit}"
        size /= 1000


# ------------------------------------------------------------------ facts ---


def info():
    tpm = SYS / "class/tpm/tpm0/tpm_version_major"
    apps = []
    for line in APPS_TABLE.read_text().splitlines():
        app_id, on, kind, _npm, label = line.split("\t")
        apps.append({"id": app_id, "label": label, "kind": kind, "on": on == "1"})
    return {
        "hostname": HOSTNAME,
        "user": USER,
        "githubUser": GITHUB_USER,
        "uefi": (SYS / "firmware/efi").is_dir(),
        "tpm": tpm.exists() and tpm.read_text().strip() == "2",
        "apps": apps,
    }


def online():
    ok, _, _ = sh("curl", "-fsS", "--max-time", "6", "-o", "/dev/null", "https://github.com")
    return ok


def split_fields(line):
    """Split one line of `nmcli -t` output, which escapes colons inside values."""
    return [p.replace("\\:", ":") for p in re.split(r"(?<!\\):", line)]


def network():
    """Whether we are online, and how: by cable, over Wi-Fi, or not at all."""
    ok, out, _ = sh("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device")
    wired, has_wifi, ssid = False, False, ""
    for line in out.splitlines() if ok else []:
        parts = split_fields(line)
        if len(parts) < 4:
            continue
        _dev, kind, status, connection = parts[:4]
        up = status.startswith("connected")
        if kind == "ethernet" and up:
            wired = True
        if kind == "wifi":
            has_wifi = True
            if up:
                ssid = connection
    return {"online": online(), "wired": wired, "wifi": has_wifi, "ssid": ssid}


def wifi_list():
    ok, out, _ = sh("nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes")
    best = {}
    for line in out.splitlines() if ok else []:
        parts = split_fields(line)
        if len(parts) < 3 or not parts[0]:
            continue
        ssid, signal, security = parts[0], int(parts[1] or 0), parts[2]
        if ssid not in best or signal > best[ssid]["signal"]:
            best[ssid] = {"ssid": ssid, "signal": signal, "secure": security not in ("", "--")}
    return sorted(best.values(), key=lambda n: -n["signal"])


def wifi_connect(ssid, password):
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]
    ok, _, err = sh(*cmd, timeout=60)
    if ok:
        return {"ok": True}
    wrong = "secrets were required" in err.lower() or "802-11-wireless-security" in err
    return {"ok": False, "error": "That password was not accepted." if wrong else "Could not join that network."}


def ssh_keys(user):
    if not USERNAME.match(user or ""):
        return {"ok": False, "error": "That doesn't look like a GitHub username."}
    ok, out, _ = sh("curl", "-fsS", "--max-time", "15", f"https://github.com/{user}.keys")
    if not ok:
        return {"ok": False, "error": f"GitHub has no account named {user}, or it could not be reached."}
    count = len(KEY_LINE.findall(out))
    if count == 0:
        return {"ok": False, "error": f"{user} has no SSH keys on GitHub. Add one at github.com/settings/keys, then check again."}
    return {"ok": True, "count": count}


def parent_disk(part):
    ok, out, _ = sh("lsblk", "-no", "PKNAME", str(part))
    name = out.split("\n")[0].strip() if ok else ""
    return f"/dev/{name}" if name else ""


def disks():
    """Internal disks, NVMe first. Never removable, USB, or the boot stick."""
    ok, src, _ = sh("findmnt", "-no", "SOURCE", "/iso")
    boot = parent_disk(src.strip()) if ok and src.strip() else ""
    ok, out, _ = sh("lsblk", "-J", "-b", "-d", "-o", "NAME,SIZE,TYPE,RM,TRAN,MODEL")
    found = []
    for d in json.loads(out).get("blockdevices", []) if ok else []:
        name, path = d["name"], f"/dev/{d['name']}"
        removable = d.get("rm") in (True, "1", 1)
        if d.get("type") != "disk" or removable or d.get("tran") == "usb" or path == boot:
            continue
        if re.match(r"^(zram|loop|ram)", name):
            continue
        found.append({
            "path": path,
            "name": name,
            "size": human(d.get("size") or 0),
            "model": (d.get("model") or "Unknown disk").strip(),
            "kind": "NVMe" if d.get("tran") == "nvme" else (d.get("tran") or "disk").upper(),
        })
    found.sort(key=lambda d: 0 if d["kind"] == "NVMe" else 1)
    earlier = DEV / "disk/by-partlabel/disk-main-luks"
    return {"disks": found, "earlier": parent_disk(earlier.resolve()) if earlier.exists() else ""}


# -------------------------------------------------------------- Tailscale ---
# Sign in from the installer, then hand the saved sign-in to the install so
# the new system is on the tailnet from its first start.


class Tailscale:
    def __init__(self):
        self.lock = threading.Lock()
        self.dir = WORK / "tailscale"
        self.state = {"state": "idle", "url": "", "qr": "", "error": ""}
        self.procs = []

    def state_file(self):
        f = self.dir / "tailscaled.state"
        return str(f) if self.state["state"] == "connected" and f.exists() else ""

    def start(self, name):
        with self.lock:
            if self.state["state"] in ("starting", "waiting", "connected"):
                return
            self.state = {"state": "starting", "url": "", "qr": "", "error": ""}
        threading.Thread(target=self._run, args=(name,), daemon=True).start()

    def cancel(self):
        for p in self.procs:
            p.terminate()
        with self.lock:
            if self.state["state"] != "connected":
                self.state = {"state": "idle", "url": "", "qr": "", "error": ""}

    def _run(self, name):
        self.dir.mkdir(parents=True, exist_ok=True)
        sock = f"--socket={self.dir}/sock"
        log = open(self.dir / "log", "w")
        daemon = subprocess.Popen(
            ["tailscaled", "--tun=userspace-networking", f"--state={self.dir}/tailscaled.state", sock],
            stdout=log, stderr=subprocess.STDOUT)
        time.sleep(2)
        up = subprocess.Popen(
            ["tailscale", sock, "up", "--ssh", f"--hostname={name}", "--timeout=15m"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.procs = [up, daemon]
        for line in up.stdout:
            found = re.search(r"https://\S+", line)
            if found and self.state["state"] == "starting":
                with self.lock:
                    self.state.update(state="waiting", url=found.group(0), qr=qr_svg(found.group(0)))
        ok = up.wait() == 0
        daemon.terminate()
        daemon.wait()
        with self.lock:
            if ok:
                self.state.update(state="connected", url="", qr="")
            elif self.state["state"] != "idle":
                self.state.update(state="failed", error="Tailscale did not connect. Try again, or skip and set it up later.")


# ---------------------------------------------------------------- sign in ---
# Optional sign-ins to GitHub and the agent CLIs, so the new machine starts
# signed in. Each login runs in its own tmux session, with one home folder
# shared by all of them. The server reads the session's screen for the
# sign-in address and any one-time code; "Use a terminal instead" (ttyd)
# attaches to the same session, so both always show the same login.
# The install copies the credential files from that home to the agent.

SIGNIN_HOME = WORK / "home"
TTYD_PORT = int(os.environ.get("AGENCY_TTYD_PORT", "7374"))
TMUX = ["tmux", "-L", os.environ.get("AGENCY_TMUX_SOCKET", "agency-signin"), "-f", str(WORK / "tmux.conf")]
TMUX_CONF = "set -g remain-on-exit on\nset -g status off\nset -g history-limit 5000\nset -g mouse on\n"

SIGNIN_TOOLS = {
    "github": {
        "label": "GitHub",
        # --insecure-storage: the installer has no keyring, and the token has
        # to be in a file to be carried over.
        "cmd": "gh auth login --hostname github.com --git-protocol https --web --insecure-storage",
        "device": True,
        # Questions answered with Enter: yes to using it for git, and "press
        # Enter to open a browser" (there is none; BROWSER=true).
        "enter": [r"Authenticate Git with your GitHub credentials\?", r"Press Enter to open"],
    },
    "claude": {"label": "Claude Code", "cmd": "claude auth login", "device": False, "enter": []},
    "codex": {"label": "Codex", "cmd": "codex login --device-auth || codex login", "device": True, "enter": []},
    "opencode": {"label": "OpenCode", "cmd": "opencode auth login", "device": False, "enter": []},
}

URL = re.compile(r"https://[^\s\"'<>│]+")
DEVICE_CODE = re.compile(r"(?<![A-Za-z0-9-])[A-Z0-9]{4}-[A-Z0-9]{4,5}(?![A-Za-z0-9-])")
ASKS_CODE = re.compile(r"paste (the |your )?(authorization )?code|enter (the |your )?(authorization )?code"
                       r"|enter your api key", re.I)


def tmux(*args, timeout=10):
    return sh(*TMUX, *args, timeout=timeout)


def as_signin_user(*cmd, timeout=30):
    """Run a command with the sign-in home, e.g. to ask who is signed in."""
    env = {**os.environ, "HOME": str(SIGNIN_HOME)}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env, cwd=SIGNIN_HOME)
        return p.returncode == 0, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return False, ""


def signed_in_as(tool):
    """None if not signed in; otherwise who (may be empty)."""
    if tool == "github":
        ok, out = as_signin_user("gh", "api", "user", "--jq", ".login")
        return out.strip() if ok else None
    if tool == "claude":
        ok, _ = as_signin_user("claude", "auth", "status")
        return "" if ok else None
    if tool == "codex":
        ok, _ = as_signin_user("codex", "login", "status")
        return "" if ok else None
    if tool == "opencode":
        try:
            auth = json.loads((SIGNIN_HOME / ".local/share/opencode/auth.json").read_text())
        except (OSError, ValueError):
            return None
        return "" if auth else None
    return None


class SignIn:
    def __init__(self):
        self.lock = threading.Lock()
        self.ttyd = None
        self.states = {tool: self.blank() for tool in SIGNIN_TOOLS}

    @staticmethod
    def blank():
        return {"state": "idle", "url": "", "qr": "", "code": "", "asks": False, "who": "", "error": "",
                "started": 0.0}

    @staticmethod
    def target(tool):
        return "=agency-" + tool  # "=": exact name, no prefix matching

    @staticmethod
    def pane(tool):
        return "=agency-" + tool + ":"

    def view(self):
        now = time.time()
        tools = []
        with self.lock:
            for tool, spec in SIGNIN_TOOLS.items():
                st = dict(self.states[tool])
                started = st.pop("started")
                st["age"] = now - started if started else 0
                tools.append({"id": tool, "label": spec["label"], **st})
        return {"tools": tools, "terminal": f"http://127.0.0.1:{TTYD_PORT}/"}

    def home(self):
        """The sign-in home if anything was signed in, else ""."""
        with self.lock:
            return str(SIGNIN_HOME) if any(s["state"] == "done" for s in self.states.values()) else ""

    def start_ttyd(self):
        if self.ttyd and self.ttyd.poll() is None:
            return
        theme = json.dumps({"background": "#ffffff", "foreground": "#15201a", "cursor": "#15201a",
                            "cursorAccent": "#ffffff", "selectionBackground": "#c6d0c8"})
        try:
            # -a: the page names the session in the address (?arg==agency-github).
            self.ttyd = subprocess.Popen(
                ["ttyd", "-i", "127.0.0.1", "-p", str(TTYD_PORT), "-W", "-a", "-O",
                 "-t", "fontSize=15", "-t", f"theme={theme}", "-t", "disableLeaveAlert=true",
                 "-t", "disableResizeOverlay=true", "-t", "titleFixed=agency",
                 *TMUX, "attach-session", "-t"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            self.ttyd = None

    def start(self, tool):
        with self.lock:
            if self.states[tool]["state"] in ("running", "done"):
                return
            self.states[tool] = {**self.blank(), "state": "running", "started": time.time()}
        SIGNIN_HOME.mkdir(parents=True, exist_ok=True)
        os.chmod(SIGNIN_HOME, 0o700)
        (WORK / "tmux.conf").write_text(TMUX_CONF)
        self.start_ttyd()
        target = self.target(tool)
        tmux("kill-session", "-t", target)
        # Wide, so that long sign-in addresses are not wrapped by the program.
        ok, _, _ = tmux("new-session", "-d", "-s", target[1:], "-x", "400", "-y", "40", "-c", str(SIGNIN_HOME),
                        "env", f"HOME={SIGNIN_HOME}", "BROWSER=true", "GH_BROWSER=true",
                        "TERM=xterm-256color", "DISABLE_AUTOUPDATER=1",
                        "sh", "-c", SIGNIN_TOOLS[tool]["cmd"])
        if not ok:
            with self.lock:
                self.states[tool].update(state="failed", error="Could not start the sign-in.")
            return
        threading.Thread(target=self._watch, args=(tool,), daemon=True).start()

    def cancel(self, tool):
        tmux("kill-session", "-t", self.target(tool))
        with self.lock:
            if self.states[tool]["state"] != "done":
                self.states[tool] = self.blank()

    def input(self, tool, text):
        text = text.replace("\r", "").replace("\n", "").strip()[:4096]
        if text:
            tmux("send-keys", "-t", self.pane(tool), "-l", text)
        tmux("send-keys", "-t", self.pane(tool), "Enter")

    def _watch(self, tool):
        spec = SIGNIN_TOOLS[tool]
        target, pane = self.target(tool), self.pane(tool)
        answered = set()
        while True:
            time.sleep(0.5)
            with self.lock:
                if self.states[tool]["state"] != "running":
                    return
            ok, out, _ = tmux("display-message", "-p", "-t", pane, "#{pane_dead}")
            if not ok:  # the session is gone: cancelled
                with self.lock:
                    if self.states[tool]["state"] == "running":
                        self.states[tool] = self.blank()
                return
            ok, screen, _ = tmux("capture-pane", "-p", "-J", "-S", "-2000", "-t", pane)
            screen = screen if ok else ""
            if out.strip() != "1":
                for pattern in spec["enter"]:
                    if pattern not in answered and re.search(pattern, screen):
                        answered.add(pattern)
                        tmux("send-keys", "-t", pane, "Enter")
                self._read(tool, screen)
                continue
            # The login program has finished. Did it work?
            who = signed_in_as(tool)
            tmux("kill-session", "-t", target)
            with self.lock:
                if who is not None:
                    self.states[tool] = {**self.blank(), "state": "done", "who": who}
                else:
                    self.states[tool] = {**self.blank(), "state": "failed", "error": "Not signed in. Try again."}
            return

    def _read(self, tool, screen):
        urls = [u.rstrip(".,;:)]") for u in URL.findall(screen)]
        codes = DEVICE_CODE.findall(URL.sub(" ", screen)) if SIGNIN_TOOLS[tool]["device"] else []
        tail = "\n".join([line for line in screen.splitlines() if line.strip()][-6:])
        with self.lock:
            st = self.states[tool]
            if urls:
                url = urls[-1]
                # A narrower terminal can wrap the address later; keep the
                # full one.
                if url != st["url"] and not st["url"].startswith(url):
                    st.update(url=url, qr=qr_svg(url))
            st["code"] = codes[-1] if codes else ""
            st["asks"] = bool(ASKS_CODE.search(tail))


# ---------------------------------------------------------------- install ---

PHASES = [
    ("Checking", "Waiting for the network"),
    ("Preparing the disk", "Partitioning and formatting"),
    ("Copying the system", "Copying the system"),
    ("Encrypting the disk", "Setting up disk encryption"),
    ("Finishing", "Finishing up"),
]


class Install:
    def __init__(self):
        self.lock = threading.Lock()
        self.total_paths = 0
        self.reset()
        threading.Thread(target=self._count_paths, daemon=True).start()

    def reset(self):
        self.state = {"state": "idle", "phase": -1, "copied": 0.0, "error": "", "log": [],
                      "recoveryKey": "", "recoveryQr": ""}
        self.copied = 0

    def _count_paths(self):
        if SYSTEM:
            ok, out, _ = sh("nix-store", "-qR", SYSTEM, timeout=120)
            self.total_paths = len(out.split()) if ok else 0

    def start(self, name, disk, user, apps, tailscale_state, signin_home):
        with self.lock:
            if self.state["state"] == "running":
                return
            self.reset()
            self.state["state"] = "running"
        cmd = [INSTALLER, "--unattended", "--force", "--yes", "--no-reboot",
               "--hostname", name, "--github-user", user, "--disk", disk, "--apps", " ".join(apps)]
        if tailscale_state:
            cmd += ["--tailscale-state", tailscale_state]
        if signin_home:
            cmd += ["--signin-home", signin_home]
        threading.Thread(target=self._run, args=(cmd,), daemon=True).start()

    def _run(self, cmd):
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
        except OSError as e:
            with self.lock:
                self.state.update(state="failed", error=str(e))
            return
        stopped = ""
        for raw in p.stdout:
            line = raw.rstrip()
            with self.lock:
                if "copying path" in line:
                    self.copied += 1
                    if self.total_paths:
                        self.state["copied"] = min(self.copied / self.total_paths, 1.0)
                    continue
                if line:
                    self.state["log"] = (self.state["log"] + [line])[-200:]
                if line.startswith("[agency] STOPPED: "):
                    stopped = line[len("[agency] STOPPED: "):]
                for i, (_title, marker) in enumerate(PHASES):
                    if line.startswith("[agency] " + marker):
                        self.state["phase"] = i
        ok = p.wait() == 0
        with self.lock:
            if ok:
                key_file = MNT / "root/luks-recovery-key.txt"
                key = key_file.read_text().strip() if key_file.exists() else ""
                self.state.update(state="done", phase=len(PHASES), copied=1.0,
                                  recoveryKey=key, recoveryQr=qr_svg(key) if key else "")
            else:
                self.state.update(state="failed", error=stopped or "The install stopped with an error.")


tailscale = Tailscale()
signin = SignIn()
install = Install()


# ------------------------------------------------------------------- HTTP ---

TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript",
         ".svg": "image/svg+xml", ".woff2": "font/woff2"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/info":
            return self.send_json(info())
        if path == "/api/network":
            return self.send_json(network())
        if path == "/api/wifi":
            return self.send_json({"networks": wifi_list()})
        if path == "/api/disks":
            return self.send_json(disks())
        if path == "/api/tailscale":
            return self.send_json(tailscale.state)
        if path == "/api/signin":
            return self.send_json(signin.view())
        if path == "/api/install":
            return self.send_json({**install.state, "phases": [title for title, _ in PHASES]})
        # Static files, from the UI directory only.
        target = (UI / (path.lstrip("/") or "index.html")).resolve()
        if UI.resolve() not in target.parents or not target.is_file():
            return self.send_json({"error": "not found"}, 404)
        data = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", TYPES.get(target.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path, data = self.path, self.body()
        if path == "/api/wifi":
            return self.send_json(wifi_connect(data.get("ssid", ""), data.get("password", "")))
        if path == "/api/keys":
            return self.send_json(ssh_keys(data.get("user", "")))
        if path == "/api/name":
            ok = bool(MACHINE_NAME.match(data.get("name", "")))
            return self.send_json({"ok": ok, "error": "" if ok else "A name can use lowercase letters, numbers and hyphens, with no spaces. For example: agency or lab-2."})
        if path == "/api/tailscale/start":
            if not MACHINE_NAME.match(data.get("name", "")):
                return self.send_json({"error": "bad request"}, 400)
            tailscale.start(data["name"])
            return self.send_json(tailscale.state)
        if path == "/api/tailscale/cancel":
            tailscale.cancel()
            return self.send_json(tailscale.state)
        found = re.fullmatch(r"/api/signin/([a-z]+)/(start|cancel|input)", path)
        if found and found.group(1) in SIGNIN_TOOLS:
            tool, verb = found.groups()
            if verb == "start":
                signin.start(tool)
            elif verb == "cancel":
                signin.cancel(tool)
            else:
                signin.input(tool, str(data.get("text", "")))
            return self.send_json(signin.view())
        if path == "/api/install":
            known = {a["id"] for a in info()["apps"]}
            apps = [a for a in data.get("apps", []) if a in known]
            valid_disks = {d["path"] for d in disks()["disks"]}
            if (data.get("disk") not in valid_disks or not USERNAME.match(data.get("user", ""))
                    or not MACHINE_NAME.match(data.get("name", ""))):
                return self.send_json({"error": "bad request"}, 400)
            install.start(data["name"], data["disk"], data["user"], apps, tailscale.state_file(), signin.home())
            return self.send_json({"ok": True})
        if path == "/api/restart":
            subprocess.Popen(["systemctl", "reboot"])
            return self.send_json({"ok": True})
        if path == "/api/poweroff":
            subprocess.Popen(["systemctl", "poweroff"])
            return self.send_json({"ok": True})
        return self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
