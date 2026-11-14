<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <img src="docs/logo.svg" alt="agency" height="96">
  </picture>
</p>

<p align="center">
  NixOS config and unattended installer for a laptop used only by AI agents.
</p>

The agents have sudo. The laptop runs with the lid closed and you reach it over SSH or Tailscale. The whole system is defined in this repo, so a bad change can be rolled back at boot and the machine can be rebuilt from a USB stick.

| Part | What it is |
|---|---|
| `agent` | The only account. Passwordless sudo. |
| Display `:1` | A virtual X11 desktop (Xvnc + Openbox) for GUI apps and computer use. |
| noVNC | The same desktop in a browser, at port 6081. |
| Tailscale | Remote access. Only SSH is open on the LAN. |
| Generations | Each rebuild adds a boot menu entry. Pick an older one to undo. |
| Installer | A USB image that erases the laptop and installs all of the above. |

## Install

Needs a USB stick (8 GB or more) and a wired network connection.

1. Add an SSH key to your GitHub account if it has none. The installer fetches your public keys from GitHub. Password login is disabled.
2. Download the `agency-installer` artifact from **Actions → Build installer ISO** and flash it with balenaEtcher or `dd`.
3. BIOS settings: Secure Boot off, UEFI boot, TPM on.
4. Boot the stick. After a 30 second countdown it erases the internal disk, installs, and reboots. Holding the power button during the countdown cancels it.
5. From another machine on the same network:

```sh
ssh agent@agency.local
sudo tailscale up --ssh
```

To skip step 5, format a second stick as FAT with the label `AGENCY` and put a one-time Tailscale auth key on it in a file named `tailscale-authkey`. With both sticks plugged in, the machine joins your tailnet on first boot.

The installer stops before touching the disk if:

- the machine's vendor doesn't match `vendorMatch` in `settings.nix`
- the disk already has an agency install
- there is no TPM 2.0, or the machine booted in legacy mode
- it found no SSH public key

`sudo agency-install --force` (shell on Alt+F2) skips the first two checks.

## Use

Install an agent CLI under the `agent` account and have it read [`AGENTS.md`](AGENTS.md). That file explains the machine to agents and lists the setup that is still to do.

```sh
gui chromium                                   # start an app on the virtual desktop
DISPLAY=:1 scrot /tmp/screen.png               # screenshot
DISPLAY=:1 xdotool mousemove 640 400 click 1   # click

cd /etc/nixos
sudo nixos-rebuild switch --flake .            # apply a config change
```

The desktop is at `http://agency:6081/vnc.html` over Tailscale. Log in to websites there yourself; the browser profile persists, so agents stay signed in.

Prebuilt binaries, AppImages and `npm install -g` work without extra steps (`nix-ld` and AppImage support are enabled). Docker and distrobox are installed.

## Status

Untested on hardware. The config evaluates, the install script passes shellcheck, and CI builds the ISO. The TPM enrolment and the virtual desktop services have not been run on a real machine.

Known gaps:

- Secure Boot is off. TPM unlock protects the data if the disk is removed, but not if someone boots another OS on the laptop.
- There is one virtual desktop, not one per agent.
- The Nvidia GPU is not configured.
- No secrets management yet.

These are listed as tasks in `AGENTS.md`.

The disk recovery key is printed at the end of the install and saved to `/root/luks-recovery-key.txt`. Move it somewhere safe.

## Other hardware

The config targets an MSI GF63 Thin 11UC. For another machine, edit [`settings.nix`](settings.nix) (host name, disk, `vendorMatch`, `githubUser`), replace [`hosts/agency/hardware.nix`](hosts/agency/hardware.nix) as described in that file, and push. CI builds a new ISO.

## Credits

NixOS, disko, Tailscale, TigerVNC, noVNC, Openbox. The logo type is [Pixelify Sans](https://github.com/eifetx/Pixelify-Sans) (SIL Open Font License).
