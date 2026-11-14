---
name: agency-system
description: How the agency machine itself is defined and changed. Use when changing system software or configuration, or when the system is broken.
---

# The system

NixOS, defined by the git repo in `/etc/nixos` (owned by you). Change the
system there, apply it with `agency rebuild` (`--test` lasts only until the
next reboot), and commit what works. Edits made outside the repo are lost or
drift from it. `/etc/nixos/AGENTS.md` describes the layout.

Every rebuild is a boot menu entry, and `agency rollback` returns to the
previous one. Changes to boot, disks, network or SSH can lock everyone out,
so be careful with those.

Much needs no rebuild at all: `npm install -g`, `uv`, `pip --user`,
`nix shell`, and Docker when it is on. `agency help` lists the rest of the
command (updates, apps, desktops, secrets).
