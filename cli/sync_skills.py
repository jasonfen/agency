"""Sync agency and user skills into every installed agent CLI.

All skills live in one canonical folder (~/.agents/skills):
  - Agency's built-in skills (agency-*) are linked there from the Nix store.
  - Any skill directory created inside an installed provider's skills folder
    (a real directory containing SKILL.md) is moved into ~/.agents/skills and
    replaced with a symlink back to it.
  - Every skill in ~/.agents/skills is symlinked into every installed
    provider's skills folder (per-skill symlinks, so provider-private folders
    like Claude Code's synced/ and .trash/ stay isolated).
  - Agency's machine instructions are linked into each installed provider,
    and Claude Code gets its default Remote Control setting when missing.

A person's own files, non-skill folders, and custom overrides are never
replaced. Dangling symlinks left behind when a skill is removed from
~/.agents/skills (or when agency retires a built-in skill) are pruned.
"""

import argparse
import fcntl
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

# Provider-internal subfolders that are not skills and should not delay --wait.
IGNORED_SUBDIRS = {"synced"}


def warn(msg):
    print(f"agency-sync-skills: {msg}", file=sys.stderr)


def safe_resolve(path):
    try:
        return path.resolve()
    except OSError:
        return Path(os.path.abspath(path))


def readlink_abs(path):
    raw = os.readlink(path)
    if os.path.isabs(raw):
        return os.path.normpath(raw)
    return os.path.normpath(os.path.join(path.parent, raw))


def is_nix_store(path_str):
    return path_str.startswith("/nix/store/")


def is_in_dir(path_str, directory):
    prefix = os.path.normpath(str(directory))
    return path_str == prefix or path_str.startswith(prefix + os.sep)


def is_in_any_dir(path_str, directories):
    return any(is_in_dir(path_str, d) for d in directories)


def is_managed_target(path_str, hub, provider_dirs):
    return (
        is_nix_store(path_str)
        or is_in_dir(path_str, hub)
        or is_in_any_dir(path_str, provider_dirs)
    )


def atomic_symlink(target, dest):
    """Create or atomically replace symlink dest -> target."""
    dest = Path(dest)
    target = str(target)
    if dest.is_symlink() and os.readlink(dest) == target:
        return
    fd, tmp_name = tempfile.mkstemp(prefix=".agency-link-", dir=dest.parent)
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        tmp.unlink()
        os.symlink(target, tmp)
        os.replace(tmp, dest)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def move_dir(src, dest):
    """Move directory src to dest, atomically when on the same filesystem."""
    try:
        os.rename(src, dest)
    except OSError:
        shutil.move(str(src), str(dest))


def has_skill_file(directory):
    return (directory / "SKILL.md").is_file()


def program_installed(program, search_dirs):
    if not program:
        return False
    for d in search_dirs:
        candidate = d / program
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return True
    return False


def build_search_dirs(home, extra_path=None):
    dirs = [
        home / ".bun/bin",
        home / ".npm-global/bin",
        home / ".local/bin",
        Path("/run/current-system/sw/bin"),
    ]
    env_path = os.environ.get("PATH", "") if extra_path is None else extra_path
    for part in env_path.split(os.pathsep):
        if part:
            p = Path(part)
            if p not in dirs:
                dirs.append(p)
    return dirs


def installed_providers(providers, home, extra_path=None):
    search_dirs = build_search_dirs(home, extra_path=extra_path)
    return [
        p
        for p in providers
        if p.get("chosen") or program_installed(p.get("program"), search_dirs)
    ]


def wait_for_fresh_skills(dirs, max_wait=2.0, fresh_window=5.0, poll=0.2):
    """Briefly wait if a brand-new subdirectory lacks SKILL.md yet.

    Avoids racing with an agent that runs `mkdir <skills>/<name>` right before
    writing `SKILL.md` inside it.
    """
    deadline = time.monotonic() + max_wait
    while True:
        now = time.time()
        pending = []
        for d in dirs:
            if not d.is_dir():
                continue
            try:
                entries = list(d.iterdir())
            except OSError:
                continue
            for entry in entries:
                if entry.name.startswith(".") or entry.name in IGNORED_SUBDIRS:
                    continue
                if entry.is_symlink() or not entry.is_dir():
                    continue
                if has_skill_file(entry):
                    continue
                try:
                    age = now - entry.stat().st_mtime
                except OSError:
                    continue
                if 0 <= age <= fresh_window:
                    pending.append(entry)
        if not pending or time.monotonic() >= deadline:
            return
        time.sleep(min(poll, max(0.0, deadline - time.monotonic())))


def link_builtin_skills(hub, builtin_skills):
    """Link agency's built-in skills into hub and prune retired nix-store links."""
    hub.mkdir(parents=True, exist_ok=True)
    for item in hub.iterdir():
        if item.is_symlink() and not item.exists() and is_nix_store(readlink_abs(item)):
            item.unlink()

    if not builtin_skills or not builtin_skills.is_dir():
        return
    for skill in sorted(builtin_skills.iterdir()):
        if skill.name.startswith(".") or not skill.is_dir():
            continue
        dest = hub / skill.name
        if dest.is_symlink():
            if is_nix_store(readlink_abs(dest)):
                atomic_symlink(skill, dest)
        elif not dest.exists():
            atomic_symlink(skill, dest)


def consolidate_provider_skills(hub, active_providers, home, all_provider_dirs):
    """Move real skill folders from provider dirs into hub, and register external links."""
    hub_resolved = safe_resolve(hub)
    for provider in active_providers:
        rel = provider.get("skills")
        if not rel:
            continue
        pdir = home / rel
        if not pdir.is_dir():
            continue
        if pdir.is_symlink() and safe_resolve(pdir) == hub_resolved:
            continue

        for entry in sorted(pdir.iterdir()):
            if entry.name.startswith("."):
                continue
            try:
                if not entry.is_symlink() and entry.is_dir():
                    if not has_skill_file(entry):
                        continue
                    dest = hub / entry.name
                    if not dest.exists() and not dest.is_symlink():
                        move_dir(entry, dest)
                        os.symlink(str(dest), entry)
                    elif dest.is_symlink():
                        if dest.exists() and safe_resolve(dest) == safe_resolve(entry):
                            # Reverse symlink (hub -> provider): flip ownership to hub.
                            dest.unlink()
                            move_dir(entry, dest)
                            os.symlink(str(dest), entry)
                        elif not dest.exists() and is_managed_target(
                            readlink_abs(dest), hub, all_provider_dirs
                        ):
                            dest.unlink()
                            move_dir(entry, dest)
                            os.symlink(str(dest), entry)
                elif entry.is_symlink() and entry.exists():
                    resolved = safe_resolve(entry)
                    if not resolved.is_dir() or not has_skill_file(resolved):
                        continue
                    res_str = str(resolved)
                    if is_managed_target(res_str, hub, all_provider_dirs):
                        continue
                    dest = hub / entry.name
                    if not dest.exists() and not dest.is_symlink():
                        os.symlink(res_str, dest)
            except OSError as exc:
                warn(f"skipping {entry}: {exc}")


def distribute_hub_skills(hub, active_providers, home, all_provider_dirs):
    """Symlink every skill in hub into each installed provider's skills dir."""
    hub_resolved = safe_resolve(hub)
    hub_skills = [
        entry
        for entry in sorted(hub.iterdir())
        if not entry.name.startswith(".") and entry.is_dir() and has_skill_file(entry)
    ]

    for provider in active_providers:
        rel = provider.get("skills")
        if not rel:
            continue
        pdir = home / rel
        if pdir.is_symlink():
            if pdir.exists() and safe_resolve(pdir) == hub_resolved:
                continue
            if not pdir.is_dir():
                warn(f"skipping {pdir}: symlink does not point to a directory")
                continue
        elif pdir.exists() and not pdir.is_dir():
            warn(f"skipping {pdir}: exists and is not a directory")
            continue
        else:
            pdir.mkdir(parents=True, exist_ok=True)

        # Prune broken managed symlinks (e.g. a skill deleted from ~/.agents/skills).
        for item in list(pdir.iterdir()):
            if item.is_symlink() and not item.exists():
                if is_managed_target(readlink_abs(item), hub, all_provider_dirs):
                    try:
                        item.unlink()
                    except OSError as exc:
                        warn(f"could not remove stale link {item}: {exc}")

        for hub_entry in hub_skills:
            dest = pdir / hub_entry.name
            target = str(hub_entry)
            try:
                if dest.is_symlink():
                    if os.readlink(dest) == target:
                        continue
                    raw_abs = readlink_abs(dest)
                    can_replace = (
                        is_nix_store(raw_abs)
                        or is_in_dir(raw_abs, hub)
                        or (
                            is_in_any_dir(raw_abs, all_provider_dirs)
                            and (not dest.exists() or safe_resolve(dest) == safe_resolve(hub_entry))
                        )
                    )
                    if can_replace:
                        atomic_symlink(target, dest)
                elif not dest.exists():
                    atomic_symlink(target, dest)
            except OSError as exc:
                warn(f"could not link {dest}: {exc}")


def link_instructions(active_providers, home, instructions):
    """Link agency's machine instructions into each installed provider."""
    if not instructions or not instructions.is_file():
        return
    target = str(instructions)
    for provider in active_providers:
        rel = provider.get("instructions")
        if not rel:
            continue
        dest = home / rel
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.is_symlink():
                if os.readlink(dest) == target:
                    continue
                if is_nix_store(readlink_abs(dest)):
                    atomic_symlink(target, dest)
            elif not dest.exists():
                atomic_symlink(target, dest)
        except OSError as exc:
            warn(f"could not link {dest}: {exc}")


def ensure_json_default(path, key, value):
    """Set key=value in JSON object file unless key is set or file is unreadable."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        existing_mode = path.stat().st_mode if path.exists() else None
        if existing_mode is None or path.stat().st_size == 0:
            data = {}
        else:
            data = json.loads(path.read_text())
            if not isinstance(data, dict) or key in data:
                return
        data[key] = value
        fd, tmp_name = tempfile.mkstemp(prefix=".agency-json-", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.write("\n")
            os.chmod(tmp_name, existing_mode & 0o7777 if existing_mode is not None else 0o644)
            os.replace(tmp_name, path)
        except BaseException:
            Path(tmp_name).unlink(missing_ok=True)
            raise
    except (OSError, ValueError):
        return


def sync(home, config, builtin_skills=None, instructions=None, wait=False, extra_path=None):
    home = Path(home)
    hub = home / config.get("hub", ".agents/skills")
    providers = config.get("providers", [])
    active = installed_providers(providers, home, extra_path=extra_path)
    all_provider_dirs = [home / p["skills"] for p in providers if p.get("skills")]

    link_builtin_skills(hub, builtin_skills)

    if wait:
        watch_dirs = [hub] + [
            home / p["skills"]
            for p in active
            if p.get("skills") and not (
                (home / p["skills"]).is_symlink()
                and safe_resolve(home / p["skills"]) == safe_resolve(hub)
            )
        ]
        wait_for_fresh_skills(watch_dirs)

    consolidate_provider_skills(hub, active, home, all_provider_dirs)
    distribute_hub_skills(hub, active, home, all_provider_dirs)
    link_instructions(active, home, instructions)

    if any(p.get("id") == "claude-code" for p in active):
        ensure_json_default(home / ".claude/settings.json", "remoteControlAtStartup", True)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="agency-sync-skills",
        description="Sync skills and machine instructions into all installed agent CLIs.",
    )
    parser.add_argument("--config", required=True, help="JSON provider catalog from modules/skills.nix")
    parser.add_argument("--skills", help="Directory of built-in agency skills")
    parser.add_argument("--instructions", help="Agency machine instructions file")
    parser.add_argument("--home", default=str(Path.home()), help="User home directory")
    parser.add_argument(
        "--wait",
        action="store_true",
        help="Wait briefly if a freshly created skill folder has no SKILL.md yet",
    )
    args = parser.parse_args(argv)

    home = Path(args.home)
    config = json.loads(Path(args.config).read_text())
    builtin_skills = Path(args.skills) if args.skills else None
    instructions = Path(args.instructions) if args.instructions else None

    lock_path = home / ".cache/agency/skills-sync.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with open(lock_path, "w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        sync(
            home=home,
            config=config,
            builtin_skills=builtin_skills,
            instructions=instructions,
            wait=args.wait,
        )


if __name__ == "__main__":
    main()
