"""agency: look after this machine.

Run `agency` for a summary of the machine and `agency help` for the commands.
It runs as the agent account and uses sudo where it must. Every change it
makes to /etc/nixos is committed, so `git log` there shows what happened.
"""

import argparse
import getpass
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path

REPO = Path("/etc/nixos")
SETTINGS = REPO / "settings.nix"
FLAKE = f"path:{REPO}#agency"
USER = os.environ.get("AGENCY_USER", "agent")
DEFAULT_REPO = "https://github.com/makors/agency"

# Written by the installer: the commit of this repo the machine came from.
SOURCE_REV = Path("/var/lib/agency/source-rev")
FIRSTBOOT = Path("/var/lib/agency/firstboot")
RECOVERY_KEY = Path("/root/luks-recovery-key.txt")

SECRETS = REPO / "secrets" / "agency.sops.json"
SOPS_CONFIG = REPO / ".sops.yaml"
HOST_KEY = Path("/etc/ssh/ssh_host_ed25519_key")
AUTHORIZED_KEYS = Path("/etc/agency/authorized_keys")
SECRET_NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")


# ------------------------------------------------------------- helpers ---


def say(msg=""):
    print(msg, flush=True)


def die(msg):
    print(f"agency: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd, check=True, capture=False, stdin=None, env=None, cwd=None):
    """Run a command. With check, stop agency if it fails."""
    result = subprocess.run(
        [str(c) for c in cmd],
        input=stdin,
        env=env,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if check and result.returncode != 0:
        if capture and result.stderr:
            sys.stderr.write(result.stderr)
        die(f"this failed: {' '.join(str(c) for c in cmd)}")
    return result


def output(cmd):
    """A command's output, or "" if it fails."""
    result = run(cmd, check=False, capture=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def tool(name):
    """Full path of a tool, for running it under sudo."""
    path = shutil.which(name)
    if not path:
        die(f"{name} is missing")
    return path


def git(*args, **kw):
    return run(["git", "-C", REPO, *args], **kw)


def host():
    return socket.gethostname()


def ask(question):
    if not sys.stdin.isatty():
        die("this needs a person at the keyboard")
    return input(question).strip()


# ------------------------------------------------------------ settings ---
# settings.nix keeps the values agency edits on one line each.


def read_setting(key):
    match = re.search(rf"^  {key} = (.*);$", SETTINGS.read_text(), re.M)
    return match.group(1) if match else None


def write_setting(key, value):
    text, n = re.subn(
        rf"^  {key} = .*;$", f"  {key} = {value};", SETTINGS.read_text(), count=1, flags=re.M
    )
    if n == 0:
        die(f"settings.nix has no one-line `{key} = ...;` to change")
    SETTINGS.write_text(text)


def setting_string(key):
    value = read_setting(key)
    return json.loads(value) if value and value.startswith('"') else ""


def setting_list(key):
    return re.findall(r'"([^"]*)"', read_setting(key) or "")


def nix_list(items):
    return "[ " + "".join(f'"{i}" ' for i in items) + "]"


def desktop_count():
    value = read_setting("desktops")
    return int(value) if value and value.isdigit() else 1


# ---------------------------------------------------------------- repo ---


def setup_identity():
    if not output(["git", "-C", REPO, "config", "user.email"]):
        git("config", "user.name", f"agency on {host()}")
        git("config", "user.email", f"{USER}@{host()}")


def ensure_repo():
    """Put /etc/nixos under git, on top of the commit it was installed from.

    The installer copies the repo as plain files. This makes it a clone of
    `repo` in settings.nix with this machine's settings as one commit on
    top, so `agency update` can pull new versions in.
    """
    if (REPO / ".git").is_dir():
        return
    url = setting_string("repo") or DEFAULT_REPO
    say(f"Linking /etc/nixos to {url} ...")
    run(["sudo", "chown", "-R", f"{USER}:users", REPO])
    git("init", "-q", "-b", "main")
    git("remote", "add", "origin", url)
    if git("fetch", "-q", "origin", "main", check=False).returncode != 0:
        shutil.rmtree(REPO / ".git")
        die(f"could not fetch {url}. Check the network and try again.")
    setup_identity()

    base = SOURCE_REV.read_text().strip() if SOURCE_REV.exists() else ""
    known = base and git("cat-file", "-e", f"{base}^{{commit}}", check=False, capture=True).returncode == 0
    if not known:
        base = "origin/main"
        say("  The commit this machine was installed from is not known, so its files")
        say("  are compared with the newest version. Check `git -C /etc/nixos show`.")
    git("reset", "-q", "--mixed", base)
    git("branch", "-q", "--set-upstream-to", "origin/main")
    commit("This machine's settings", ".")
    say("Done. /etc/nixos is now a git repo.")


def commit(message, *paths):
    git("add", "-A", "--", *paths)
    if git("diff", "--cached", "--quiet", check=False).returncode != 0:
        git("commit", "-q", "-m", message)


def uncommitted():
    return output(["git", "-C", REPO, "status", "--porcelain"]) if (REPO / ".git").is_dir() else ""


def rebuild(mode="switch"):
    say(f"Rebuilding the system ({mode}) ...")
    result = run(["sudo", tool("nixos-rebuild"), mode, "--flake", FLAKE], check=False)
    if result.returncode != 0:
        die("the rebuild failed. The running system did not change.")
    if mode == "switch":
        say("Done. The new system is running and is the newest boot menu entry.")


# ------------------------------------------------------------ commands ---


def cmd_status(args):
    say(f"agency  {host()}")
    ts_ip = output(["tailscale", "ip", "-4"]).split("\n")[0]
    say(f"  ssh        ssh {USER}@{host()}" + (f"   (tailnet {ts_ip})" if ts_ip else "   (not on a tailnet)"))

    for n in range(1, desktop_count() + 1):
        state = output(["systemctl", "is-active", f"agency-display@{n}.service"]) or "stopped"
        say(f"  desktop :{n}  http://{host()}:{6080 + n}/vnc.html   {state}")

    profile = output(["readlink", "/nix/var/nix/profiles/system"])
    generation = re.search(r"system-(\d+)-link", profile)
    head = output(["git", "-C", REPO, "log", "-1", "--format=%h %s (%cr)"]) or "not linked yet, run: agency update"
    say(f"  system     generation {generation.group(1) if generation else '?'}, repo at {head}")
    say(f"  apps       {' '.join(setting_list('apps')) or 'none'}")
    names = secret_names()
    say(f"  secrets    {', '.join(names) if names else 'none'}")

    notes = []
    if FIRSTBOOT.exists():
        notes.append("First-start setup is still running: journalctl -fu agency-firstboot")
    if run(["sudo", "-n", "test", "-e", RECOVERY_KEY], check=False, capture=True).returncode == 0:
        notes.append("The disk recovery key is still on disk. A person should run: agency recovery-key")
    if uncommitted():
        notes.append("/etc/nixos has changes that are not committed.")
    for note in notes:
        say(f"  ! {note}")


def cmd_update(args):
    ensure_repo()
    if uncommitted():
        commit("Local changes, saved before an update", ".")
        say("Committed the local changes in /etc/nixos first.")
    url = setting_string("repo") or DEFAULT_REPO
    if output(["git", "-C", REPO, "remote", "get-url", "origin"]) != url:
        git("remote", "set-url", "origin", url)
        say(f"Updating from {url} (repo in settings.nix).")
    say("Fetching ...")
    git("fetch", "-q", "origin")
    behind = int(output(["git", "-C", REPO, "rev-list", "--count", "HEAD..@{u}"]) or 0)
    if behind:
        say(f"{behind} new commit(s):")
        git("log", "--format=  %h %s", "HEAD..@{u}")
        if git("rebase", "-q", "@{u}", check=False).returncode != 0:
            git("rebase", "--abort", check=False)
            die(
                "your local commits conflict with the update. Nothing changed.\n"
                "Resolve it by hand: cd /etc/nixos && git rebase @{u}"
            )
    if args.packages:
        say("Updating nixpkgs and the other inputs ...")
        run(["nix", "flake", "update", "--flake", f"path:{REPO}"])
        commit("Update flake inputs", "flake.lock")
    if not behind and not args.packages:
        say("Already up to date. (`agency update --packages` also updates nixpkgs.)")
        return
    rebuild()


def cmd_rebuild(args):
    if uncommitted():
        say("Note: /etc/nixos has changes that are not committed. Commit them when they work.")
    rebuild("test" if args.test else "switch")
    if args.test:
        say("Applied until the next reboot. Run `agency rebuild` to keep it.")


def cmd_rollback(args):
    say("Switching back to the previous system ...")
    run(["sudo", tool("nixos-rebuild"), "switch", "--rollback"])
    say("Done. /etc/nixos did not change: revert the commit that broke things,")
    say("or the next rebuild brings the problem back.")


def catalog():
    result = run(["nix", "eval", "--json", f"path:{REPO}#appCatalog"], capture=True)
    return json.loads(result.stdout)


def cmd_apps(args):
    apps = catalog()
    chosen = setting_list("apps")
    if args.action == "list":
        for app in apps:
            mark = "*" if app["id"] in chosen else " "
            say(f" {mark} {app['id']:<14} {app['label']}")
        say("\n* is on. Change with: agency apps add|remove <id>")
        return

    by_id = {app["id"]: app for app in apps}
    if args.id not in by_id:
        die(f"no app called {args.id}. See: agency apps")
    app = by_id[args.id]
    ensure_repo()
    if args.action == "add":
        if args.id in chosen:
            die(f"{args.id} is already on")
        chosen.append(args.id)
    else:
        if args.id not in chosen:
            die(f"{args.id} is not on")
        chosen.remove(args.id)
    write_setting("apps", nix_list(chosen))
    commit(f"{'Add' if args.action == 'add' else 'Remove'} app {args.id}", "settings.nix")

    if app["kind"] == "npm":
        verb = "install" if args.action == "add" else "uninstall"
        run(["npm", verb, "-g", app["npm"]])
        say(f"Done: {app['label']}.")
    else:
        rebuild()


def cmd_desktop(args):
    count = desktop_count()
    if args.action == "list":
        for n in range(1, count + 1):
            state = output(["systemctl", "is-active", f"agency-display@{n}.service"]) or "stopped"
            say(f"  :{n}  http://{host()}:{6080 + n}/vnc.html   {state}")
        return
    ensure_repo()
    if args.action == "add":
        count += 1
        write_setting("desktops", str(count))
        commit(f"Add desktop :{count}", "settings.nix")
        rebuild()
        say(f"Desktop :{count} is ready. Use it with: gui -d {count} <app>   or   DISPLAY=:{count}")
        say(f"Watch it at http://{host()}:{6080 + count}/vnc.html")
    else:
        if count == 1:
            die("desktop :1 always stays")
        write_setting("desktops", str(count - 1))
        commit(f"Remove desktop :{count}", "settings.nix")
        rebuild()
        say(f"Removed desktop :{count}.")


def cmd_recovery_key(args):
    if run(["sudo", "test", "-e", RECOVERY_KEY], check=False).returncode != 0:
        say("The recovery key is no longer on this machine. If it is lost, make a new one")
        say("(this also removes the old one):")
        say("  sudo systemd-cryptenroll --wipe-slot=recovery --recovery-key <the LUKS partition>")
        return
    if not sys.stdin.isatty():
        die("only a person should see the recovery key. Run this yourself over SSH.")
    key = run(["sudo", "cat", RECOVERY_KEY], capture=True).stdout.strip()
    say("Disk recovery key. If the TPM stops unlocking the disk (a BIOS update, a new")
    say("motherboard), this is the only way in. Store it in your password manager.\n")
    say(f"  {key}\n")
    run(["qrencode", "-t", "UTF8", "-m", "2", key], check=False)
    if ask('Type "saved" once it is stored, and agency deletes it from this disk: ').lower() == "saved":
        run(["sudo", "shred", "-u", RECOVERY_KEY])
        say("Deleted.")
    else:
        say("Kept. Run `agency recovery-key` again when it is stored.")


# ------------------------------------------------------------- secrets ---
# Secrets live encrypted in secrets/agency.sops.json, so they can be
# committed and pushed. The machine's SSH host key decrypts them at boot
# (sops-nix, see modules/secrets.nix); the ed25519 keys that can log in can
# decrypt them too, so a copy of the repo is never the only way back.


def secret_names():
    if not SECRETS.exists():
        return []
    return sorted(k for k in json.loads(SECRETS.read_text()) if k != "sops")


def recipients():
    keys = [output(["ssh-to-age", "-i", f"{HOST_KEY}.pub"])]
    if AUTHORIZED_KEYS.exists():
        for line in AUTHORIZED_KEYS.read_text().splitlines():
            if line.startswith("ssh-ed25519 "):
                result = run(["ssh-to-age"], stdin=line + "\n", check=False, capture=True)
                keys.append(result.stdout.strip() if result.returncode == 0 else "")
    keys = list(dict.fromkeys(k for k in keys if k.startswith("age1")))
    if not keys:
        die(f"no age key: is {HOST_KEY}.pub there?")
    return keys


def sops_env():
    identity = run(["sudo", tool("ssh-to-age"), "-private-key", "-i", HOST_KEY], capture=True)
    return dict(os.environ, SOPS_AGE_KEY=identity.stdout.strip())


def load_secrets():
    if not SECRETS.exists():
        return {}
    result = run(
        ["sops", "decrypt", "--input-type", "json", "--output-type", "json", SECRETS],
        env=sops_env(),
        capture=True,
    )
    data = json.loads(result.stdout)
    data.pop("sops", None)
    return data


def save_secrets(data):
    SOPS_CONFIG.write_text(
        "# Who can read secrets/: this machine's SSH host key and the ed25519 keys\n"
        "# that can log in. Written by `agency secret`.\n"
        "creation_rules:\n"
        "  - path_regex: secrets/.*\\.sops\\.json$\n"
        f"    age: {','.join(recipients())}\n"
    )
    if not data:
        SECRETS.unlink(missing_ok=True)
        return
    result = run(
        [
            "sops", "encrypt",
            "--input-type", "json", "--output-type", "json",
            "--filename-override", SECRETS.relative_to(REPO),
            "/dev/stdin",
        ],
        stdin=json.dumps(data),
        cwd=REPO,
        capture=True,
    )
    SECRETS.parent.mkdir(exist_ok=True)
    SECRETS.write_text(result.stdout)


def cmd_secret(args):
    if args.action == "list":
        names = secret_names()
        say("\n".join(names) if names else "No secrets yet. Add one with: agency secret set NAME")
        return
    if args.action == "get":
        data = load_secrets()
        if args.name not in data:
            die(f"no secret called {args.name}")
        print(data[args.name])
        return

    if not SECRET_NAME.match(args.name):
        die("use a name like OPENAI_API_KEY: capitals, digits and _")
    ensure_repo()
    data = load_secrets()
    if args.action == "set":
        if sys.stdin.isatty():
            value = getpass.getpass(f"Value for {args.name} (not shown): ")
        else:
            value = sys.stdin.read().rstrip("\n")
        if not value:
            die("empty value, nothing changed")
        data[args.name] = value
        message = f"Set secret {args.name}"
    else:
        if data.pop(args.name, None) is None:
            die(f"no secret called {args.name}")
        message = f"Remove secret {args.name}"
    save_secrets(data)
    commit(message, ".sops.yaml", "secrets")
    if args.no_rebuild:
        say("Saved. It reaches /run/secrets after the next `agency rebuild`.")
        return
    rebuild()
    if args.action == "set":
        say(f"{args.name} is in /run/secrets/{args.name}, and in ${args.name} in new shells.")


def cmd_setup_repo(args):
    ensure_repo()


# ---------------------------------------------------------------- main ---


def main():
    if os.geteuid() == 0:
        # Run as the agent account so files in /etc/nixos stay theirs.
        os.execvp("runuser", ["runuser", "-u", USER, "--", "agency", *sys.argv[1:]])

    parser = argparse.ArgumentParser(
        prog="agency",
        description="Look after this agency machine. With no command: a summary.",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")

    sub.add_parser("status", help="summary of this machine (the default)")

    p = sub.add_parser("update", help="pull the newest agency from `repo` in settings.nix and rebuild")
    p.add_argument("--packages", action="store_true", help="also update nixpkgs and other inputs")

    p = sub.add_parser("rebuild", help="apply the files in /etc/nixos")
    p.add_argument("--test", action="store_true", help="only until the next reboot (a safe trial)")

    sub.add_parser("rollback", help="go back to the previous system")

    p = sub.add_parser("apps", help="list, add or remove optional software")
    p.add_argument("action", nargs="?", default="list", choices=["list", "add", "remove"])
    p.add_argument("id", nargs="?")

    p = sub.add_parser("desktop", help="list, add or remove virtual desktops")
    p.add_argument("action", nargs="?", default="list", choices=["list", "add", "remove"])

    p = sub.add_parser("secret", help="encrypted secrets that agents can read")
    p.add_argument("action", nargs="?", default="list", choices=["list", "set", "get", "remove"])
    p.add_argument("name", nargs="?")
    p.add_argument("--no-rebuild", action="store_true", help="save without applying yet")

    sub.add_parser("recovery-key", help="show the disk recovery key once, then delete it")
    sub.add_parser("setup-repo", help=argparse.SUPPRESS)
    sub.add_parser("help", help="show this help")

    args = parser.parse_args()
    if args.command == "help":
        parser.print_help()
        return
    if args.command == "apps" and args.action != "list" and not args.id:
        die("which app? See: agency apps")
    if args.command == "secret" and args.action != "list" and not args.name:
        die(f"usage: agency secret {args.action} NAME")

    handlers = {
        None: cmd_status,
        "status": cmd_status,
        "update": cmd_update,
        "rebuild": cmd_rebuild,
        "rollback": cmd_rollback,
        "apps": cmd_apps,
        "desktop": cmd_desktop,
        "secret": cmd_secret,
        "recovery-key": cmd_recovery_key,
        "setup-repo": cmd_setup_repo,
    }
    handlers[args.command](args)
    if args.command is None:
        say("\nCommands: update, rebuild, rollback, apps, desktop, secret, recovery-key. See: agency help")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
