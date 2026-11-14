---
name: agency-system
description: Change, update or repair the agency machine itself. Read this before you install system software, edit anything in /etc/nixos, add an app, or when something about the system is broken.
---

# Changing this machine

The whole system is defined by the git repo in `/etc/nixos`. Change the
system by changing files there and rebuilding. Do not edit `/etc` by hand or
install system software outside the repo: those changes are lost or drift
from the repo. The full guide is `/etc/nixos/AGENTS.md`.

## The agency command

```sh
agency                    # summary: desktops, apps, secrets, warnings
agency rebuild            # apply the files in /etc/nixos
agency rebuild --test     # apply until the next reboot only (safe trial)
agency rollback           # go back to the previous system
agency update             # pull the newest agency and rebuild
agency apps               # list optional software; agency apps add docker
agency desktop add        # another virtual desktop
agency secret set NAME    # see the agency-secrets skill
```

## Before you change something

- You may not need a rebuild at all. `npm install -g`, `uv tool install`,
  `pip install --user` and `nix shell nixpkgs#<pkg>` all work without one, and
  so do `docker run` and `distrobox` when the docker app is on.
- For a change to boot, disks, network or SSH, use `agency rebuild --test`
  first and check that SSH still works from a second session.
- Commit what you change in `/etc/nixos` once it works, with a message that
  says why. Never commit a plain-text secret.

## If something breaks

Every rebuild is a boot menu entry. `agency rollback` switches back now. If
the machine does not come back, a person picks an older entry at boot. Then
revert the commit that caused it, or the next rebuild brings it back.

A downloaded Linux binary that fails with a missing library: add the library
to `programs.nix-ld.libraries` in `modules/agents.nix` and rebuild.
