# The USB installer: the standard NixOS minimal installer, plus a setup
# screen that starts as soon as the stick has booted.
#
#   installer/ui/            the setup screen (a web page)
#   installer/server.py      what the page talks to; runs on localhost only
#   installer/agency-install.sh   does the install; also a text wizard
#
# The stick boots into a kiosk: one fullscreen browser window showing the
# setup screen, with no desktop around it. If the kiosk cannot start (no
# usable graphics), the text wizard takes over the same console.
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
  target = self.nixosConfigurations.agency.config;

  # The app catalog as a plain table the installer can read.
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
  # space. The installer compares the chosen apps with this to decide
  # whether the new machine must rebuild itself on first start.
  bakedSystem = lib.concatMapStrings (id: id + " ") (
    lib.sort lib.lessThan (map (app: app.id) (lib.filter (app: !(app ? npm) && isOn app) catalog))
  );

  tools = [
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

  agency-install = pkgs.writeShellApplication {
    name = "agency-install";
    runtimeInputs = tools;
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
      export AGENCY_REV=${lib.escapeShellArg (self.rev or (lib.removeSuffix "-dirty" (self.dirtyRev or "")))}

      ${builtins.readFile ./agency-install.sh}
    '';
  };

  port = "7373";

  # The kiosk's one program: wait for the server, then show the page.
  kiosk = pkgs.writeShellScript "agency-kiosk" ''
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      ${pkgs.curl}/bin/curl -fs -o /dev/null http://127.0.0.1:${port}/ && break
      ${pkgs.coreutils}/bin/sleep 0.5
    done
    exec ${pkgs.chromium}/bin/chromium \
      --kiosk --app=http://127.0.0.1:${port}/ \
      --ozone-platform=wayland --disable-gpu \
      --user-data-dir=/tmp/agency-kiosk \
      --no-first-run --noerrdialogs --disable-translate \
      --disable-features=Translate --disable-pinch \
      --overscroll-history-navigation=0
  '';

  # The text wizard on the first console. Used for unattended sticks, and as
  # the fallback when the kiosk stops.
  textInstaller = {
    description = "agency installer (text)";
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
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  config = lib.mkMerge [
    {
      nixpkgs.hostPlatform = "x86_64-linux";
      image.baseName = lib.mkForce "agency-installer";

      # Put the prebuilt system on the stick.
      isoImage.storeContents = [ target.system.build.toplevel ];

      # A lighter compression level than the default (19). The ISO comes out
      # a little larger and builds several times faster.
      isoImage.squashfsCompression = "zstd -Xcompression-level 6";

      environment.systemPackages = [ agency-install ];

      boot.kernelParams = [
        "quiet"
        "loglevel=3"
      ];

      # Skip the boot menu (installer, recovery, memory test ...) and start
      # the installer straight away.
      boot.loader.timeout = lib.mkForce 0;
    }

    # An unattended stick asks nothing, so it needs no screen: run the
    # installer on the console as soon as the stick has booted.
    (lib.mkIf settings.unattended {
      systemd.services.agency-text = textInstaller // {
        wantedBy = [ "multi-user.target" ];
      };
    })

    # Otherwise: the setup screen.
    (lib.mkIf (!settings.unattended) {
      systemd.services.agency-setup-server = {
        description = "Backend for the setup screen";
        wantedBy = [ "multi-user.target" ];
        before = [ "cage-tty1.service" ];
        path = tools ++ [ agency-install ];
        environment = {
          HOME = "/root";
          AGENCY_UI = "${./ui}";
          AGENCY_HOSTNAME = settings.hostName;
          AGENCY_USER = settings.user;
          AGENCY_GITHUB_USER = settings.githubUser;
          AGENCY_APPS = "${appsTable}";
          AGENCY_SYSTEM = "${target.system.build.toplevel}";
        };
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./server.py}";
          Restart = "always";
        };
      };

      # The browser draws no text at all unless the system has a font
      # configuration and at least one font, even though the page brings
      # its own fonts. The minimal installer switches both off.
      fonts.fontconfig.enable = lib.mkForce true;
      fonts.packages = [ pkgs.dejavu_fonts ];

      # cage shows one program fullscreen. "-s" keeps Ctrl+Alt+F2 working,
      # and the pixman renderer needs no graphics driver beyond a screen.
      services.cage = {
        enable = true;
        user = "nixos";
        program = kiosk;
        extraArguments = [ "-s" ];
        environment.WLR_RENDERER = "pixman";
      };

      # If the kiosk stops for any reason, fall back to the text wizard.
      systemd.services."cage-tty1".unitConfig = {
        OnFailure = [ "agency-text.service" ];
        OnSuccess = [ "agency-text.service" ];
      };
      systemd.services.agency-text = textInstaller;
    })
  ];
}
