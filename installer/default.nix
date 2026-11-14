# The USB installer. It is the standard NixOS minimal installer plus one
# service that runs installer/agency-install.sh as soon as it boots.
#
# The finished system is built in advance and stored on the stick, so the
# install copies files and downloads nothing except your SSH public keys.
{
  config,
  lib,
  pkgs,
  modulesPath,
  self,
  settings,
  ...
}:
let
  target = self.nixosConfigurations.${settings.hostName}.config;

  agency-install = pkgs.writeShellApplication {
    name = "agency-install";
    runtimeInputs = [
      config.system.build.nixos-install
      config.nix.package
      config.systemd.package
      pkgs.coreutils
      pkgs.util-linux
      pkgs.curl
      pkgs.gnugrep
    ];
    text = ''
      export AGENCY_DISK=${lib.escapeShellArg settings.disk}
      export AGENCY_VENDOR=${lib.escapeShellArg settings.vendorMatch}
      export AGENCY_GITHUB_USER=${lib.escapeShellArg settings.githubUser}
      export AGENCY_SSH_KEYS=${pkgs.writeText "ssh-keys" (lib.concatLines settings.sshKeys)}
      export AGENCY_WIPE=${target.system.build.destroyFormatMount}/bin/disko-destroy-format-mount
      export AGENCY_SYSTEM=${target.system.build.toplevel}
      export AGENCY_SOURCE=${self}

      ${builtins.readFile ./agency-install.sh}
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  image.baseName = lib.mkForce "${settings.hostName}-installer";

  # Put the prebuilt system on the stick.
  isoImage.storeContents = [ target.system.build.toplevel ];

  environment.systemPackages = [ agency-install ];

  # Run the install on the first console as soon as the stick has booted.
  systemd.services.agency-autoinstall = {
    description = "Unattended install of ${settings.hostName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "systemd-user-sessions.service"
    ];
    wants = [ "network-online.target" ];
    conflicts = [ "getty@tty1.service" ];
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${agency-install}/bin/agency-install";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TimeoutStartSec = "infinity";
    };
  };
}
