<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/agency-dark.svg">
    <img src="docs/agency.svg" alt="agency" height="96">
  </picture>
</p>

<p align="center">
  Turns a spare laptop into a computer for your agents.
</p>

Agents are bad at sharing a computer. They want the mouse, the screen and the browser at the same moment you do, and on your own machine you can't really let them run with full permissions. So give them a different one. Flash this onto a USB stick, boot a spare laptop from it, and a few minutes later it's a NixOS box where the agents have root and a desktop of their own. You SSH in when they need you, or open their desktop in a browser tab to type a password.

If an agent breaks the system, reboot and pick yesterday's version from the boot menu.

## Install

1. Make sure your GitHub account has an SSH key on it, because that's how you'll log in.
2. Download the ISO from **Actions → Build installer ISO** and flash it to a USB stick.
3. In the BIOS, turn Secure Boot off and TPM on, then plug in Ethernet.
4. Boot the stick. It wipes the internal disk and installs on its own, so don't boot it on a machine you care about.

Once it has rebooted:

```sh
ssh agent@agency.local
sudo tailscale up --ssh
```

[docs/install.md](docs/install.md) covers what the installer checks before it wipes anything, and how to skip the SSH step entirely.

## Use

Install whichever agent CLI you like and point it at [AGENTS.md](AGENTS.md), which tells it how the machine works and what's left to set up.

```sh
gui chromium                                   # open an app on the agents' desktop
sudo nixos-rebuild switch --flake /etc/nixos   # apply a change to the system
```

Their desktop lives at `http://agency:6081/vnc.html` once you're on Tailscale.

## Does it work

Don't know yet. CI builds the installer, but nobody has booted it on a real machine, so expect the first install to trip on something. It should run on any x86-64 laptop or PC that has UEFI and a TPM 2.0 chip.
