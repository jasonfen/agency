<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/agency-dark.svg">
    <img src="docs/agency.svg" alt="agency" height="96">
  </picture>
</p>

<p align="center">
  A laptop that only AI agents use, as a NixOS config and a USB installer.
</p>

Agents get sudo and a virtual desktop. You reach the machine over SSH or Tailscale and watch the desktop in a browser. Every change can be undone from the boot menu.

## Install

1. Add an SSH key to your GitHub account.
2. Download the ISO from **Actions → Build installer ISO** and flash it to a USB stick.
3. In the BIOS, turn Secure Boot off and TPM on. Plug in Ethernet.
4. Boot the stick. It erases the internal disk and installs by itself.

```sh
ssh agent@agency.local
sudo tailscale up --ssh
```

More in [docs/install.md](docs/install.md).

## Use

```sh
gui chromium                              # open an app on the virtual desktop
sudo nixos-rebuild switch --flake /etc/nixos   # apply a config change
```

The desktop is at `http://agency:6081/vnc.html`. Agents should start with [AGENTS.md](AGENTS.md).

## Status

Builds in CI. Not yet tested on real hardware.

Works on any x86-64 laptop or PC with UEFI and a TPM 2.0 chip. Names and keys are set in `settings.nix`.
