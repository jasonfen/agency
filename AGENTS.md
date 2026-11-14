# AGENTS.md

You are an agent working on **agency**, a laptop whose only users are AI
agents. No human sits at it. You have full control: the `agent` account has
passwordless `sudo`. This file tells you how the machine works and how to
change it.

## The one rule

**The system is defined by the git repo in `/etc/nixos`. Change the system
by changing the repo, then rebuilding.** Do not edit files under `/etc` or
install system software by hand; such changes are lost or silently diverge
from the repo, which is published for others to reproduce.

```sh
cd /etc/nixos       # owned by this account, no sudo needed to edit
# edit .nix files
agency rebuild          # apply now
agency rebuild --test   # apply until next reboot (safe trial)
agency rollback         # back to the previous system
```

`agency` with no arguments summarises the machine; `agency help` lists the
rest. It rebuilds from `path:/etc/nixos`, so new files count before they are
committed. Use it instead of `sudo nixos-rebuild --flake /etc/nixos`, which
reads the repo through git as root and can refuse it, because the repo
belongs to this account.

The configuration is always called `agency`, whatever this machine is named;
its own name is `hostName` in `settings.nix`.

Every rebuild is a new boot menu entry. If the machine does not come back
after a change, a human picks the previous entry at boot. Before a risky
change (boot, disk, network, SSH), use `test` first and confirm SSH still
works from a second session.

Commit what you change. Never commit a plain-text secret: tokens, private
keys and passwords go in through `agency secret set NAME` (see Secrets).

`/etc/nixos` tracks the agency repo on GitHub (`repo` in `settings.nix`),
with this machine's settings as commits on top. `agency update` pulls new
versions and rebuilds; `agency update --packages` also updates nixpkgs.

## What does not need a rebuild

Anything in the home directory. Use these freely:

- `npm install -g <pkg>` installs to `~/.npm-global` (already on `PATH`).
- `uv` / `pip install --user` for Python tools.
- `nix shell nixpkgs#<pkg>` for a tool you need once.
- `docker run ...` for services and throwaway environments, and
  `distrobox create -i ubuntu:24.04` when software insists on a normal
  distro. Both need the `docker` app (see below).

Downloaded Linux binaries and AppImages run directly (`nix-ld` and AppImage
support are enabled). If a binary fails with a missing library, add the
library to `programs.nix-ld.libraries` in `modules/agents.nix`.

## Optional apps

`apps.nix` is a catalog of optional software, and `apps` in `settings.nix`
lists the ids that are switched on. The human picked a first set in the
installer. `agency apps add <id>` switches one on and `agency apps remove <id>`
off; to offer something new, add an entry to `apps.nix`.

Agent CLIs in the catalog are the `npm` kind: they are installed with
`npm install -g` into this account, not by a rebuild, so they can update
themselves.

Right after an install, the choices are still being applied in the
background. Check with `journalctl -u agency-firstboot`.

## GUI apps and computer use

GUI apps run on virtual X11 desktops, 1280x800, with Openbox. Desktop `:1`
always runs; `desktops` in `settings.nix` sets how many (`agency desktop add`
adds one). Agents that use the GUI at the same time should each take their
own desktop.

```sh
gui chromium                      # start an app on $DISPLAY, or :1
gui -d 2 chromium                 # start an app on :2
DISPLAY=:1 scrot /tmp/screen.png  # screenshot
DISPLAY=:1 xdotool mousemove 640 400 click 1
DISPLAY=:1 xdotool type 'hello'
```

A human can watch or take over desktop `:N` at
`http://<this machine's name>:<6080+N>/vnc.html` over Tailscale (`:1` is
port 6081). When a site needs a login or 2FA, ask the human to do it there;
the browser profile persists, so you stay signed in afterwards.

The `agency-desktop` skill has the details.

## Secrets

API keys and tokens are stored encrypted in `secrets/agency.sops.json`,
readable by this machine's SSH host key and the ed25519 keys that can log
in. At boot each is decrypted to `/run/secrets/NAME`; new shells have it as
`$NAME`.

```sh
agency secret                       # list names
agency secret set NAME              # asks for the value, or reads stdin
agency secret remove NAME
```

## Skills and instructions for agents

`skills/` holds skills (`agency-desktop`, `agency-system`, `agency-secrets`)
that are linked into `~/.claude/skills`, `~/.codex/skills`,
`~/.agents/skills` and `~/.config/opencode/skills`. A short note pointing at
this file is linked as `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and
`~/.config/opencode/AGENTS.md`. Files a person put in those places are left
alone. Add a skill by adding a folder to `skills/` and rebuilding.

## Layout of the repo

| Path | What it holds |
| --- | --- |
| `settings.nix` | Names, SSH keys, chosen apps: the values that differ per machine |
| `apps.nix` | Catalog of optional software |
| `hosts/agency/` | Boot, hardware, disk layout |
| `modules/agents.nix` | The agent account and tools |
| `modules/apps.nix`, `modules/firstboot.nix` | Apply the chosen apps |
| `modules/remote.nix` | SSH, Tailscale, firewall |
| `modules/desktop.nix` | The virtual desktops |
| `modules/cli.nix`, `cli/agency.py` | The `agency` command |
| `modules/secrets.nix`, `secrets/` | Encrypted secrets (sops-nix) |
| `modules/skills.nix`, `skills/` | Skills and instructions for agent CLIs |
| `modules/laptop.nix` | Lid, sleep, thermals |
| `modules/dashboard.nix`, `dashboard/` | The web dashboard and terminal, over Tailscale (`server.py`, `ui/`) |
| `modules/screen.nix` | The status screen on the laptop's own display (`dashboard/ui/screen.*`) |
| `installer/` | The USB installer: setup screen (`ui/`), its backend (`server.py`), and the install script |

## Facts about this machine

- Hardware varies. Run `lscpu`, `free -h`, `lsblk` and `lspci` to see what
  you have. A discrete Nvidia card, if present, is not set up.
- Disk is LUKS-encrypted and unlocked by the TPM at boot. The recovery key
  is in `/root/luks-recovery-key.txt` until the human runs `agency recovery-key`,
  which shows it once and deletes it. Do not read that file yourself.
- Firewall: from the LAN only SSH (22) and mDNS are open. Everything is open
  over `tailscale0`. Bind new services to all interfaces and they are
  reachable over Tailscale only.
- Check `free -h` and `nproc` before starting large parallel builds. As a
  guide, 8 cores and 32 GB handle roughly 4 to 6 heavy agents at once.

## Work still to do

These were planned but deliberately left out of the first install so that it
had fewer ways to fail. Do them one at a time, each as its own commit.

1. **T3 Code as a service.** If it was chosen, the `t3` command is
   installed; make it a systemd user service so it survives reboots.
2. **Secure Boot.** Add lanzaboote, then re-enrol the TPM. Until then TPM
   unlock protects the disk if it is removed, but not against someone booting
   another OS on this laptop.
3. **Battery care.** On a laptop, try to cap charge at 80%. How depends on
   the vendor (look under `/sys/class/power_supply/BAT*/`).
4. **Nvidia.** Only if GPU compute is wanted: `hardware.nvidia` with PRIME
   offload, and remove the nouveau blacklist in `hosts/agency/hardware.nix`.
