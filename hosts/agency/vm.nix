# The machine as a virtual machine, to try agency without a spare computer:
#
#   nix run github:makors/agency#vm
#
# A window opens with the machine's own screen. Log in from another terminal
# with the password "agency":
#
#   ssh -p 2222 agent@localhost
#
# Everything here applies to that VM only, never to an installed machine.
# The VM keeps its disk in ./agency.qcow2; delete the file to start fresh.
#
# It is for looking around: the agent account, the `agency` command, the
# desktops, and the dashboard once you run `sudo tailscale up` in it.
# /etc/nixos holds a copy of this repo, as on a real machine, but it
# describes a real machine's disks, so rebuilding the system
# (`agency rebuild`, `agency update`, system apps) is not part of the trial.
#
# The first time it has a network, the VM sends one anonymous `vm_started`
# event (docs/install.md, "Counting installs"). DO_NOT_TRACK=1 on the
# command line turns it off: DO_NOT_TRACK=1 nix run github:makors/agency#vm
{
  lib,
  pkgs,
  self,
  settings,
  ...
}:
let
  count = pkgs.callPackage ../../pkgs/count.nix {
    rev = self.rev or (lib.removeSuffix "-dirty" (self.dirtyRev or ""));
  };
in
{
  virtualisation.vmVariant = {
    networking.hostName = lib.mkForce "agency";

    # A known password, and password login over SSH, since nobody's keys
    # are in a VM built from the public repo.
    users.users.${settings.user}.password = "agency";
    services.openssh.settings.PasswordAuthentication = lib.mkForce true;
    services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce true;

    # What the installer does on a real machine: put this repo in /etc/nixos.
    systemd.services.agency-vm-repo = {
      description = "Copy the agency repo to /etc/nixos";
      wantedBy = [ "multi-user.target" ];
      before = [ "agency-dashboard.service" ];
      unitConfig.ConditionPathExists = "!/etc/nixos/flake.nix";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /etc/nixos
        ${pkgs.coreutils}/bin/cp -rT ${self} /etc/nixos
        chmod -R u+w /etc/nixos
        chown -R ${settings.user}:users /etc/nixos
      '';
    };

    # One anonymous `vm_started` event per VM disk, so we can count trials
    # (installer/count.sh). The ID and the marker live on the VM's disk, so
    # later boots of the same VM send nothing. The host's DO_NOT_TRACK comes
    # in through QEMU's firmware config (see qemu.options below).
    boot.kernelModules = [ "qemu_fw_cfg" ];
    systemd.services.agency-vm-count = {
      description = "Count this VM once";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "!/var/lib/agency/vm-count/vm_started";
      # "exec": boot never waits for this.
      serviceConfig.Type = "exec";
      environment.AGENCY_COUNT_DIR = "/var/lib/agency/vm-count";
      script = ''
        dnt=/sys/firmware/qemu_fw_cfg/by_name/opt/agency/do_not_track/raw
        if [ -r $dnt ]; then DO_NOT_TRACK=$(cat $dnt); export DO_NOT_TRACK; fi
        ${count}/bin/agency-count --once vm_started || true
      '';
    };

    virtualisation = {
      qemu.options = [ ''-fw_cfg "name=opt/agency/do_not_track,string=''${DO_NOT_TRACK:-0}"'' ];
      memorySize = 4096;
      cores = 4;
      diskSize = 20 * 1024;
      forwardPorts = [
        {
          from = "host";
          # This computer only: the password is public.
          host.address = "127.0.0.1";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };
  };
}
