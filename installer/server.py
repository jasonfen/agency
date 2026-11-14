"""Backend for the setup screen.

The setup screen is a web page (installer/ui) shown fullscreen on the machine
being installed. This small server, on localhost only, gives that page what
it needs: the network state, SSH keys, the list of disks, a Tailscale
sign-in, and a way to start the install and watch it.

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
HOSTNAME = os.environ.get("AGENCY_HOSTNAME", "agency")
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


def wifi_list():
    ok, out, _ = sh("nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes")
    best = {}
    for line in out.splitlines() if ok else []:
        parts = [p.replace("\\:", ":") for p in re.split(r"(?<!\\):", line)]
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

    def start(self):
        with self.lock:
            if self.state["state"] in ("starting", "waiting", "connected"):
                return
            self.state = {"state": "starting", "url": "", "qr": "", "error": ""}
        threading.Thread(target=self._run, daemon=True).start()

    def cancel(self):
        for p in self.procs:
            p.terminate()
        with self.lock:
            if self.state["state"] != "connected":
                self.state = {"state": "idle", "url": "", "qr": "", "error": ""}

    def _run(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        sock = f"--socket={self.dir}/sock"
        log = open(self.dir / "log", "w")
        daemon = subprocess.Popen(
            ["tailscaled", "--tun=userspace-networking", f"--state={self.dir}/tailscaled.state", sock],
            stdout=log, stderr=subprocess.STDOUT)
        time.sleep(2)
        up = subprocess.Popen(
            ["tailscale", sock, "up", "--ssh", f"--hostname={HOSTNAME}", "--timeout=15m"],
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

    def start(self, disk, user, apps, tailscale_state):
        with self.lock:
            if self.state["state"] == "running":
                return
            self.reset()
            self.state["state"] = "running"
        cmd = [INSTALLER, "--unattended", "--force", "--yes", "--no-reboot",
               "--github-user", user, "--disk", disk, "--apps", " ".join(apps)]
        if tailscale_state:
            cmd += ["--tailscale-state", tailscale_state]
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
        if path == "/api/online":
            return self.send_json({"online": online()})
        if path == "/api/wifi":
            return self.send_json({"networks": wifi_list()})
        if path == "/api/disks":
            return self.send_json(disks())
        if path == "/api/tailscale":
            return self.send_json(tailscale.state)
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
        if path == "/api/tailscale/start":
            tailscale.start()
            return self.send_json(tailscale.state)
        if path == "/api/tailscale/cancel":
            tailscale.cancel()
            return self.send_json(tailscale.state)
        if path == "/api/install":
            known = {a["id"] for a in info()["apps"]}
            apps = [a for a in data.get("apps", []) if a in known]
            valid_disks = {d["path"] for d in disks()["disks"]}
            if data.get("disk") not in valid_disks or not USERNAME.match(data.get("user", "")):
                return self.send_json({"error": "bad request"}, 400)
            install.start(data["disk"], data["user"], apps, tailscale.state_file())
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
