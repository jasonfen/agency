# AGENTS.md

You are an agent working on **agency**, a laptop whose only users are AI
agents. No human sits at it. You have full control: the `agent` account has
passwordless `sudo`. This file tells you how the machine works and how to
change it.

## The one rule

**The system is defined by the repo in `/etc/nixos`. Change the system by
changing the repo, then rebuilding.** Do not edit files under `/etc` or
install system software by hand; such changes are lost or silently diverge
from the repo, which is published for others to reproduce.

```sh
cd /etc/nixos
# edit .nix files
sudo nixos-rebuild switch --flake .    # apply now
sudo nixos-rebuild test --flake .      # apply until next reboot (safe trial)
```

Every rebuild is a new boot menu entry. If the machine does not come back
after a change, a human picks the previous entry at boot. Before a risky
change (boot, disk, network, SSH), use `test` first and confirm SSH still
works from a second session.

Commit what you change. Never commit secrets: no tokens, private keys or
passwords anywhere in this repo.

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
installer. To add one, put its id in that list and rebuild; to offer
something new, add an entry to `apps.nix`.

Agent CLIs in the catalog are the `npm` kind: they are installed with
`npm install -g` into this account, not by a rebuild, so they can update
themselves.

Right after an install, the choices are still being applied in the
background. Check with `journalctl -u agency-firstboot`.

## GUI apps and computer use

There is one virtual desktop, X11 display `:1`, 1280x800, with Openbox.

```sh
gui chromium                      # start an app on the desktop
DISPLAY=:1 scrot /tmp/screen.png  # screenshot
DISPLAY=:1 xdotool mousemove 640 400 click 1
DISPLAY=:1 xdotool type 'hello'
```

A human can watch or take over at `http://agency:6081/vnc.html` over
Tailscale. When a site needs a login or 2FA, ask the human to do it there;
the browser profile persists, so you stay signed in afterwards.

## Layout of the repo

| Path | What it holds |
| --- | --- |
| `settings.nix` | Names, SSH keys, chosen apps: the values that differ per machine |
| `apps.nix` | Catalog of optional software |
| `hosts/agency/` | Boot, hardware, disk layout |
| `modules/agents.nix` | The agent account and tools |
| `modules/apps.nix`, `modules/firstboot.nix` | Apply the chosen apps |
| `modules/remote.nix` | SSH, Tailscale, firewall |
| `modules/desktop.nix` | The virtual desktop |
| `modules/laptop.nix` | Lid, sleep, thermals |
| `installer/` | The USB installer: setup screen (`ui/`), its backend (`server.py`), and the install script |

## Facts about this machine

- Hardware varies. Run `lscpu`, `free -h`, `lsblk` and `lspci` to see what
  you have. A discrete Nvidia card, if present, is not set up.
- Disk is LUKS-encrypted and unlocked by the TPM at boot. The recovery key
  is in `/root/luks-recovery-key.txt` until the human has stored it elsewhere.
- Firewall: from the LAN only SSH (22) and mDNS are open. Everything is open
  over `tailscale0`. Bind new services to all interfaces and they are
  reachable over Tailscale only.
- Check `free -h` and `nproc` before starting large parallel builds. As a
  guide, 8 cores and 32 GB handle roughly 4 to 6 heavy agents at once.

## Work still to do

These were planned but deliberately left out of the first install so that it
had fewer ways to fail. Do them one at a time, each as its own commit.

1. **Move the repo under git.** `/etc/nixos` is a plain copy. After
   `gh auth login`, ask the human which repo to track (their fork, if they
   have one), clone it to `~/agency`, carry over `settings.nix`, and rebuild
   from there.
2. **Store the disk recovery key.** Ask the human to copy
   `/root/luks-recovery-key.txt` into their password manager, then delete it.
3. **T3 Code as a service.** If it was chosen, the `t3` command is
   installed; make it a systemd user service so it survives reboots.
4. **Secrets.** Add sops-nix so API keys live encrypted in the repo and are
   readable by agents at runtime.
5. **Secure Boot.** Add lanzaboote, then re-enrol the TPM. Until then TPM
   unlock protects the disk if it is removed, but not against someone booting
   another OS on this laptop.
6. **Battery care.** On a laptop, try to cap charge at 80%. How depends on
   the vendor (look under `/sys/class/power_supply/BAT*/`).
7. **Nvidia.** Only if GPU compute is wanted: `hardware.nvidia` with PRIME
   offload, and remove the nouveau blacklist in `hosts/agency/hardware.nix`.
8. **More desktops.** One display per concurrent GUI agent: turn the three
   services in `modules/desktop.nix` into templates (`:2`, `:3`, ...).
