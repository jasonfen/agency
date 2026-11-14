# Install details

## What you need

- An x86-64 laptop or PC with UEFI and TPM 2.0, a USB stick (8 GB or more), a wired network connection.
- An SSH key on the GitHub account named in `settings.nix`. The installer fetches the public keys from `github.com/<githubUser>.keys`. Password login is disabled.

## What the installer does

1. Checks the machine (see below).
2. Counts down 30 seconds. Holding the power button cancels.
3. Erases the internal disk and creates an encrypted btrfs volume. The disk's model and size are shown during the countdown.
4. Copies the prebuilt system from the stick. Nothing is downloaded except your SSH keys.
5. Binds the disk encryption to the TPM, so the machine boots unattended.
6. Reboots.

## When it stops

The installer stops before touching the disk if:

- `vendorMatch` is set in `settings.nix` and the machine's vendor doesn't match
- the machine has more than one internal disk and none is named in `settings.nix` (it lists them; pick one with `sudo agency-install --disk /dev/NAME`)
- the disk already has an agency install, so a stick left plugged in can't reinstall in a loop
- there is no TPM 2.0, or the machine booted in legacy mode
- it found no SSH public key

`sudo agency-install --force`, from the shell on Alt+F2, skips the vendor and already-installed checks.

By default there is no vendor check: the stick installs on any machine it boots, after the countdown. Label it.

## Joining Tailscale without logging in

Format a second stick as FAT with the label `AGENCY`. Put a one-time Tailscale auth key on it in a file named `tailscale-authkey`. Boot with both sticks plugged in. The machine joins your tailnet on first boot, and the installer also saves the disk recovery key to that stick.

## Disk recovery key

It is printed at the end of the install and saved to `/root/luks-recovery-key.txt`. Move it to a password manager and delete the file.

## Limits

- Secure Boot is off. TPM unlock protects the data if the disk is removed, but not if someone boots another OS on the laptop.
- The remaining setup work is listed in [AGENTS.md](../AGENTS.md).
