# Trying agency, and running it on NixOS you already have

## Try it in a virtual machine

On any x86-64 Linux with Nix and KVM, this starts agency in a window, with nothing to install. The first run downloads a few GB:

```sh
nix --extra-experimental-features 'nix-command flakes' run github:makors/agency#vm
```

The window shows the machine's own screen. Log in from another terminal, with the password `agency`:

```sh
ssh -p 2222 agent@localhost
```

From there `agency` shows the machine, `gui chromium` starts a browser on its desktop, and `sudo tailscale up` puts the dashboard and the desktop on your tailnet. The SSH port is open to your own computer only.

The VM is for looking around. `/etc/nixos` is there, but it describes a real machine's disks, so rebuilding the system (`agency rebuild`, `agency update`, apps that change the system) does not work in it. Its disk is `agency.qcow2` in the folder you started it from; delete that file to start fresh.

## Run it on a machine that already has NixOS

The installer erases a disk and lays it out its own way. If the machine already runs NixOS, or you want your own disk layout, you can keep the disk as it is: agency becomes the machine's configuration, with your hardware file in place of the installer's.

This makes the whole machine an agency machine. It gets an `agent` account with passwordless sudo, SSH with keys only, NetworkManager, Tailscale and a firewall, a status screen on its display, and it never sleeps. Your files and other accounts stay. Use a machine that is meant for agents.

1. Put the repo in `/etc/nixos`, keeping the old configuration next to it:

   ```sh
   sudo mv /etc/nixos /etc/nixos.old
   sudo git clone https://github.com/makors/agency /etc/nixos
   sudo chown -R "$USER" /etc/nixos
   cd /etc/nixos
   ```

2. Describe this machine in `hosts/local/`. When that folder exists, it is used instead of the installer's hardware and disk files:

   ```sh
   mkdir hosts/local
   nixos-generate-config --show-hardware-config > hosts/local/hardware-configuration.nix
   ```

   Then write `hosts/local/default.nix`, with the boot loader lines and the `stateVersion` from your old `configuration.nix`:

   ```nix
   { ... }:
   {
     imports = [ ./hardware-configuration.nix ];

     boot.loader.systemd-boot.enable = true;
     boot.loader.efi.canTouchEfiVariables = true;

     system.stateVersion = "25.11";
   }
   ```

3. In `settings.nix`, set `hostName`, and put your SSH public key in `sshKeys`. Password login over SSH is off, so without a key there you cannot log in as `agent`. Choose `apps` while you are there.

4. Commit, and switch:

   ```sh
   git add -A && git commit -m "This machine"
   sudo nixos-rebuild switch --flake path:/etc/nixos#agency
   ```

Then `ssh agent@<hostName>`, and the rest is as on an installed machine: `agency update` keeps your commit on top of the newest agency, and agents change the system by editing `/etc/nixos`.

What you do not get this way is what the installer sets up on the disk: encryption unlocked by the TPM, and the btrfs layout. Whatever your disk has, it keeps.

To go back to your old configuration, put it back and switch to it:

```sh
sudo rm -rf /etc/nixos && sudo mv /etc/nixos.old /etc/nixos
sudo nixos-rebuild switch   # add --flake /etc/nixos#<name> if it was a flake
```

To go back for one boot only, pick an entry from before agency in the boot menu.
