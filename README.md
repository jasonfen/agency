# agency

A NixOS laptop whose only users are AI agents.

A personal computer is built around a person at the screen. This one is built
around agents: they have full control of it, it runs lid-closed around the
clock, and people only visit over the network. The whole machine is this
repo, so it can be rebuilt, rolled back, or copied from one `git clone`.

> **Status: not yet tested on hardware.** The configuration evaluates and the
> install script passes lint, but nothing here has booted on a real machine.
> Expect to fix things on the first install.

## What you get

- **Agents with full control.** One account, `agent`, with passwordless sudo.
- **Undo for everything.** Each system change is a new boot entry; pick an
  older one at boot if a change breaks the machine.
- **A desktop per machine, not per person.** A virtual X11 desktop that
  agents drive with `xdotool` and screenshots, and that you can watch in a
  browser tab.
- **Reachable from anywhere, exposed to no one.** SSH on the LAN, everything
  else over Tailscale.
- **Runs normal Linux software.** `nix-ld`, AppImage support, Docker and
  distrobox are on, so downloaded binaries and `npm install -g` work.
- **Encrypted disk that boots unattended**, unlocked by the TPM chip.

## Install

You need the target laptop, a USB stick (8 GB or more), and a network cable.

1. **Add an SSH key to your GitHub account** if it has none. The installer
   installs the public keys from `github.com/<githubUser>.keys`; password
   login is off.
2. **Get the ISO.** On GitHub open *Actions → Build installer ISO → latest
   run* and download the `agency-installer` artifact. Unzip it.
3. **Flash it** to the USB stick with balenaEtcher or `dd`.
4. **Prepare the laptop.** In the BIOS: Secure Boot off, UEFI boot, TPM on.
   Plug in the network cable and power.
5. **Boot from the stick.** The installer checks the machine, counts down 30
   seconds, erases the internal disk, installs, and reboots. Hold the power
   button during the countdown to cancel.
6. **Log in** from another computer on the same network:

   ```sh
   ssh agent@agency.local
   sudo tailscale up --ssh     # prints a link; open it to join your tailnet
   ```

After that the machine is reachable as `agency` from any device on your
tailnet, and the virtual desktop is at `http://agency:6081/vnc.html`.

### Then hand it to an agent

Install an agent CLI in the `agent` account and tell it to read `AGENTS.md`,
which lists the remaining setup work. For Claude Code, the install command is
in the [official docs](https://docs.claude.com/en/docs/claude-code/overview).

### Optional: fully hands-off

Format a second USB stick as FAT with the volume label `AGENCY` and put a
file named `tailscale-authkey` on it containing a one-time Tailscale auth
key. Plug in both sticks. The machine joins your tailnet on first boot, and
the installer also saves the disk recovery key to that stick.

### What the installer refuses to do

It stops, without touching the disk, if any of these is true:

- the machine's vendor does not match `vendorMatch` in `settings.nix`
- the disk already holds an agency install (so a stick left plugged in
  cannot reinstall in a loop)
- there is no TPM 2.0, or the machine booted in legacy mode
- no SSH public key could be found

Running `sudo agency-install --force` from the installer's shell (Alt+F2)
skips the first two checks.

## Changing the machine

Edit the repo on the machine and rebuild:

```sh
cd /etc/nixos
sudo nixos-rebuild switch --flake .
```

## Adapting it to another computer

1. Edit `settings.nix`: host name, disk, `vendorMatch`, `githubUser`.
2. Replace `hosts/agency/hardware.nix` (the file says how).
3. Push. GitHub Actions builds a new ISO.

## Things to know

- **Secure Boot is off**, so TPM unlock protects the data if the disk is
  removed, but not against someone who boots another operating system on the
  laptop itself. Adding Secure Boot is on the to-do list in `AGENTS.md`.
- **The disk recovery key** is shown at the end of the install and stored in
  `/root/luks-recovery-key.txt`. Copy it somewhere safe, then delete the file.
- **Agents hold whatever you sign them in to.** Prefer credentials made for
  this machine (a new SSH key, scoped tokens) so you can revoke them alone.
- **Never commit secrets** to this repo.

## Layout

```
settings.nix          values that differ per machine
flake.nix             ties it together
hosts/agency/         boot, hardware, disk layout
modules/              agents, remote access, virtual desktop, laptop behaviour
installer/            the self-installing USB image
AGENTS.md             instructions for agents working on the machine
```
