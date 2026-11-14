# The USB installer. It is the standard NixOS minimal installer plus one
# service that runs installer/agency-install.sh as soon as it boots.
#
# The finished system is built in advance and stored on the stick, so the
# install itself copies files and downloads nothing but your SSH public keys.
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

  # The app catalog as a plain table the installer script can read.
  catalog = import ../apps.nix { inherit pkgs settings; };
  isOn = app: lib.elem app.id settings.apps;
  appsTable = pkgs.writeText "apps.tsv" (
    lib.concatMapStrings (
      app:
      lib.concatStringsSep "\t" [
        app.id
        (if isOn app then "1" else "0")
        (if app ? npm then "npm" else "system")
        (app.npm or "-")
        app.label
      ]
      + "\n"
    ) catalog
  );
  # Sorted ids of the system apps in the prebuilt system, each followed by a
  # space. The installer compares the wizard's choice with this to decide
  # whether the new machine must rebuild itself on first start.
  bakedSystem = lib.concatMapStrings (id: id + " ") (
    lib.sort lib.lessThan (map (app: app.id) (lib.filter (app: !(app ? npm) && isOn app) catalog))
  );

  agency-install = pkgs.writeShellApplication {
    name = "agency-install";
    runtimeInputs = [
      config.system.build.nixos-install
      config.nix.package
      config.systemd.package
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.util-linux
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.gum
      pkgs.qrencode
      pkgs.networkmanager
      pkgs.tailscale
    ];
    text = ''
      export AGENCY_HOSTNAME=${lib.escapeShellArg settings.hostName}
      export AGENCY_USER=${lib.escapeShellArg settings.user}
      export AGENCY_UNATTENDED=${if settings.unattended then "1" else "0"}
      export AGENCY_DISK=${lib.escapeShellArg settings.disk}
      export AGENCY_VENDOR=${lib.escapeShellArg settings.vendorMatch}
      export AGENCY_GITHUB_USER=${lib.escapeShellArg settings.githubUser}
      export AGENCY_SSH_KEYS=${pkgs.writeText "ssh-keys" (lib.concatLines settings.sshKeys)}
      export AGENCY_APPS=${appsTable}
      export AGENCY_BAKED_SYSTEM=${lib.escapeShellArg bakedSystem}
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

  # A larger console font, so the wizard and its QR codes are readable on a
  # high-resolution laptop screen, and a quiet kernel so it stays readable.
  console = {
    earlySetup = true;
    font = "ter-v24n";
    packages = [ pkgs.terminus_font ];
  };
  boot.kernelParams = [
    "quiet"
    "loglevel=3"
  ];

  # Run the installer on the first console as soon as the stick has booted.
  systemd.services.agency-autoinstall = {
    description = "Install ${settings.hostName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "NetworkManager.service"
      "systemd-user-sessions.service"
    ];
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
