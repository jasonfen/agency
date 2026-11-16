# Install details

## What you need

- An x86-64 laptop or PC with UEFI and TPM 2.0, and a disk of 20 GB or more. A virtual machine works too; see [Installing in a VM](#installing-in-a-vm).
- A USB stick, 8 GB or more.
- Internet during the install. A cable is easiest; the wizard can also join Wi-Fi.
- A GitHub account with an SSH key on it. Password login is disabled, and the machine accepts the keys from `github.com/<you>.keys`.

On a Mac or Linux, `curl -fsSL https://agency.makors.xyz/flash | sh` downloads the newest ISO and writes it with [Caligula](https://github.com/ifd3f/caligula), which checks the ISO's SHA-256, lets you pick the stick, and verifies it afterwards. The ISO stays in `~/Downloads` for the next stick.

Otherwise download the ISO from [agency.makors.xyz](https://agency.makors.xyz) (newest build: `https://iso.makors.xyz/latest/agency-installer.iso`, details in `latest.json` next to it) and flash it with balenaEtcher or `dd`. In Rufus, choose **DD Image mode** when it asks; its ISO mode produces a stick that fails to boot.

## The setup screen

The stick shows a boot menu for three seconds, then starts a setup screen on the laptop's own display. If the screen stays black or freezes at boot (some Nvidia and hybrid-graphics laptops), start again and pick the **safe graphics, nomodeset** entry in that menu.

The setup screen works with the keyboard alone (Tab, arrows, Space, Enter) or with a mouse. Its first screen sets the keyboard layout, with a field to try it; the installed machine keeps that layout for its own screen and the disk prompt at boot. Password fields have **Show password**, so a key in the wrong place shows up before it matters. Then it goes through seven steps:

1. **Network.** If there is no connection it offers to join Wi-Fi, including a hidden network (**Other network…**). WPA-Enterprise networks are joined from the console instead; see [below](#if-something-goes-wrong).
2. **Name and login.** A name for the machine, your GitHub username, and a password for the machine's own screen (Ctrl+Alt+F2). SSH still uses your keys.
3. **Disk.** Pick the disk to erase from a list showing size and model. Disks smaller than 20 GB are shown but cannot be picked.
4. **Tailscale.** Optional. A QR code appears; scan it with your phone and approve the device. The sign-in is carried over to the installed system. The machine joins your tailnet under the name from step 2, so that name cannot be changed after this.
   The machine joins with [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh) on, so over Tailscale your tailnet policy decides who may log in, not your GitHub keys. The default policy lets you into your own devices but asks for a browser check every 12 hours, which agents logging in from another machine cannot answer; the rule under [If something goes wrong](#if-something-goes-wrong) skips it.
5. **Apps.** Pick agents (Claude Code, Codex and others) and tools (browser, Docker and so on). The list comes from [`apps.nix`](../apps.nix).
6. **Sign in.** Optional. GitHub, and Codex if you picked it: scan the code with your phone and type the short code it shows. Claude Code and OpenCode sign in later from the dashboard.
7. **Review.** A summary of the answers. Nothing is erased until you press **Erase disk and install** there; that button never responds to Enter by accident.

![The disk, Tailscale, apps, review, installing and done screens](setup-screens.png)

After the install it shows the disk recovery key as text and as a QR code. Save it.

If the screen cannot start, for example on a machine whose graphics the installer does not support, the same questions appear as a text wizard. You can also reach a shell with Ctrl+Alt+F2 and run `sudo agency-install` yourself.

## Installing in a VM

The installer runs in a virtual machine as it does on a laptop, but most hypervisors' defaults do not meet its needs. Before the first start, set the VM up with:

- **UEFI firmware** (OVMF), not BIOS (SeaBIOS).
- **Secure Boot off.**
- **A TPM 2.0** (a vTPM).
- **A disk of 20 GB or more**, on a virtio, SATA, SCSI or NVMe controller.
- 4 GB of memory or more, and a network the VM can reach the internet on.

Attach the ISO as a CD/DVD drive or a USB disk.

- **Proxmox.** In the VM's System tab, BIOS *OVMF (UEFI)*, add an EFI disk with *Pre-Enroll keys* unticked (ticked turns Secure Boot on), and add a TPM State, version v2.0. Machine type q35.
- **QEMU/KVM, virt-manager.** Firmware *UEFI* without "secboot" in its name, and add a TPM (emulated, version 2.0, backed by `swtpm`).
- **VirtualBox.** In System, tick *Enable EFI*, set TPM to *v2.0* and Secure Boot off (VirtualBox 7 and later).
- **Hyper-V.** A *Generation 2* VM. In Security, untick *Enable Secure Boot* and tick *Enable Trusted Platform Module*.
- **VMware.** Firmware *UEFI* with Secure Boot off. A vTPM needs the VM to be encrypted first (Workstation and Fusion: VM Settings, Access Control, Encrypt; ESXi: a key provider), then add a Trusted Platform Module.

If the setup screen says a setting is missing, it is one of these, in the VM's settings.

## After the first start

The stick carries a prebuilt system, so apps you added in the wizard are installed in the background the first time the machine starts. That can take ten minutes. Watch it with:

```sh
journalctl -fu agency-firstboot
```

When it is done, `/etc/nixos` is linked to this repo on GitHub, so `agency update` pulls new versions. To update from your fork instead, set `repo` in `/etc/nixos/settings.nix`; the next `agency update` switches to it.

## A stick that asks nothing

Fork the repo and edit `settings.nix`:

```nix
hostName = "lab";
githubUser = "you";
apps = [ "chromium" "docker" "claude-code" ];
unattended = true;
```

Push, and GitHub Actions builds your ISO. It boots, counts down 30 seconds, erases the disk and installs. Holding the power button during the countdown cancels.

Unattended installs choose the NVMe disk, or the SATA disk if there is no NVMe. They stop without touching anything if:

- `vendorMatch` is set and the machine's vendor doesn't match
- the machine already has an agency install, so a stick left plugged in can't reinstall in a loop
- there are two disks of the same kind and none is named in `settings.nix`
- no SSH public key was found

`sudo agency-install --unattended --force`, from the shell on Alt+F2, skips the first two checks. If the earlier install is on a different disk from the new target, `--force` erases that one as well. A stick like this installs on any machine it boots, so label it.

To join Tailscale unattended, format a second stick as FAT with the label `AGENCY` and put a one-time auth key on it in a file named `tailscale-authkey`. The installer also saves the disk recovery key to that stick.

## Counting installs

agency sends a few anonymous events to PostHog, so we can count how many sticks get written, how many installs finish, and how many of those machines start.

- The flash command sends two: when it starts and when the stick is written. They carry the OS and CPU type.
- The installer sends one when setup first has a network, one when the install starts and one when it finishes or fails. They carry the computer's maker and model, and the last one the apps picked.
- The new machine sends one, the first time it starts with a network. After that it sends nothing.
- The [try-it VM](existing-nixos.md) sends one, the first time it has a network. Its ID and the note that it was sent stay on the VM's disk, so it sends nothing on later starts; deleting `agency.qcow2` makes a new VM that counts again.

The ID is random for each run, and nothing else goes with them: no names, keys or addresses. Set `DO_NOT_TRACK=1` to turn them off (`curl -fsSL https://agency.makors.xyz/flash | DO_NOT_TRACK=1 sh`, `sudo DO_NOT_TRACK=1 agency-install` on the stick, or `DO_NOT_TRACK=1 nix run github:makors/agency#vm`).

## If something goes wrong

- **The stick doesn't boot.** Turn off legacy/CSM boot and Secure Boot. If you wrote it with Rufus, write it again in DD Image mode.
- **The screen stays black or freezes at boot.** Pick **safe graphics, nomodeset** in the stick's boot menu.
- **"No internal disk was found."** If the BIOS has the SATA or storage mode set to *RAID* or *Intel RST* (common on laptops sold with Windows), switch it to *AHCI*. (A Windows already on the machine may not start after that switch; switching back brings it back.)
- **"TPM 1.2 found".** agency needs TPM 2.0. Some machines can switch the TPM to 2.0 in the BIOS; most older ones cannot.
- **"The TPM did not accept the disk key".** The TPM is there but refused, for example after too many failed attempts, or a buggy firmware TPM. Clearing the TPM in the BIOS may help. Or choose **Install with the recovery key only**: the disk is still encrypted, but asks for the recovery key at every start. Bind it to the TPM later with the `systemd-cryptenroll` command below.
- **WPA-Enterprise Wi-Fi** (a username as well as a password, as at work or university). Press Ctrl+Alt+F2 and add the network there; Ctrl+Alt+F1 goes back to the setup screen, which then shows you connected. For the usual PEAP setup:

  ```sh
  sudo nmcli connection add type wifi con-name work ssid 'NETWORK' \
    wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 \
    802-1x.identity 'USERNAME' 802-1x.password 'PASSWORD'
  sudo nmcli connection up work
  ```

  The installed system keeps the network.
- **The install stops.** The screen says why. The whole install output is in `/tmp/agency-setup/install.log` on the stick's system (Ctrl+Alt+F2, then `less /tmp/agency-setup/install.log`). Going back and installing again, on the same disk or another, starts over cleanly.
- **The machine asks for a disk password at boot.** The TPM no longer recognizes it, usually after a BIOS update or a change to Secure Boot, or it was installed with the recovery key only. Type the recovery key, then bind the disk to the TPM again:

  ```sh
  sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-main-luks
  ```

- **SSH over Tailscale says `tailnet policy does not permit you to SSH to this node`.** Your tailnet policy has no `ssh` rule for the machine, which happens once the default policy has been replaced. Add one in the [policy file](https://login.tailscale.com/admin/acls/file), inside its outer braces. This one lets you into the devices you own, without a browser check that would lock agents out:

  ```json
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot", "root"]
    }
  ]
  ```

  `ssh agent@<name>.local` on the same network still works with your keys meanwhile.

- **An app is missing after the first start.** `agency` lists any that failed to install then, and how to try again.

- **Something else.** [Open an issue](https://github.com/makors/agency/issues/new) with the computer's model and what you saw.

## Limits

- Secure Boot must be off. TPM unlock protects the data if the disk is removed, but not if someone boots another OS on the machine.
- The disk recovery key is also saved to `/root/luks-recovery-key.txt`. Run `agency recovery-key` over SSH: it shows the key once and deletes the file.
- The remaining setup work is listed in [AGENTS.md](../AGENTS.md).
