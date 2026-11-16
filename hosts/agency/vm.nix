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
{
  lib,
  pkgs,
  self,
  settings,
  ...
}:
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

    virtualisation = {
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
