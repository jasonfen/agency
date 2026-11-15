# The virtual desktops. Each is an X11 display that exists only in memory,
# and it is where GUI apps run. Agents drive one with xdotool and
# screenshots; you watch or take over from a browser, through Selkies.
#
# Display :1 is always there. `desktops` in settings.nix sets how many run
# (:1, :2, ...), so agents that use the GUI at the same time each get their
# own. `agency desktop add` adds one.
#
#   agents:  gui chromium              start an app on :1 (or on $DISPLAY)
#            gui -d 2 chromium         start an app on :2
#            DISPLAY=:1 xdotool ...    click and type
#            DISPLAY=:1 scrot x.png    screenshot
#   you:     http://<hostName>:6081/   desktop :1 (6082 is :2, ...)
#
# Ports: display :N is web port 6080+N, over Tailscale only (see
# remote.nix). The X server itself listens on no port at all.
#
# X11 is deliberate: it lets one program see and control another, which is
# what computer use needs and what Wayland forbids.
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  count = settings.desktops or 1;

  # `gui [-d N] <command>`: run a program on a virtual desktop, detached.
  gui = pkgs.writeShellScriptBin "gui" ''
    if [ "''${1:-}" = "-d" ]; then
      export DISPLAY=":''${2#:}"
      shift 2
    elif [ -z "''${DISPLAY:-}" ]; then
      export DISPLAY=:1
    fi
    if [ $# -eq 0 ]; then
      echo "usage: gui [-d N] <command> [args ...]" >&2
      exit 2
    fi
    exec ${pkgs.util-linux}/bin/setsid -f "$@" >/dev/null 2>&1
  '';

  selkies = pkgs.callPackage ../pkgs/selkies.nix { };
  width = lib.head (lib.splitString "x" settings.desktopGeometry);
  height = lib.last (lib.splitString "x" settings.desktopGeometry);

  # Selkies streams display :N to a browser at port 6080+N. The size stays
  # fixed whatever the browser's window: agents count on their coordinates
  # and screenshots, so a person who opens a desktop must not resize it.
  # Audio, printing and gamepads are off: the desktops have none.
  viewer = pkgs.writeShellScript "agency-selkies" ''
    exec ${lib.getExe selkies} \
      --addr 0.0.0.0 --port $((6080 + $1)) \
      --enable-basic-auth false \
      --manual-resolution true --manual-width ${width} --manual-height ${height} \
      --audio-enabled false --microphone-enabled false \
      --gamepad-enabled false --webcam-enabled false \
      --printing-enabled false \
      --ui-title "Desktop :$1"
  '';

  # One desktop is three services, started and stopped together.
  part = description: execStart: {
    inherit description;
    partOf = [ "agency-desktop@%i.target" ];
    serviceConfig = {
      User = settings.user;
      Restart = "always";
      RestartSec = 2;
      ExecStart = execStart;
    };
  };
in
{
  systemd.targets."agency-desktop@" = {
    description = "Virtual desktop :%i";
    wants = [
      "agency-display@%i.service"
      "agency-wm@%i.service"
      "agency-selkies@%i.service"
    ];
  };

  # The display server, in memory only. Local programs reach it through its
  # socket in /tmp/.X11-unix; it listens on no network port.
  systemd.services."agency-display@" =
    part "Virtual desktop :%i (Xvfb)"
      "${pkgs.xorg-server}/bin/Xvfb :%i -screen 0 ${settings.desktopGeometry}x24 -nolisten tcp";

  # A window manager that only draws, moves and resizes windows.
  systemd.services."agency-wm@" =
    lib.recursiveUpdate (part "Window manager for desktop :%i (Openbox)" "${pkgs.openbox}/bin/openbox")
      {
        after = [ "agency-display@%i.service" ];
        bindsTo = [ "agency-display@%i.service" ];
        environment.DISPLAY = ":%i";
      };

  # Browser access to the desktop. No password, like the display: the port
  # is reachable over Tailscale only. Each desktop gets its own runtime
  # directory, because Selkies keeps sockets there with fixed names.
  systemd.services."agency-selkies@" =
    lib.recursiveUpdate (part "Browser access to desktop :%i (Selkies)" "${viewer} %i")
      {
        after = [ "agency-display@%i.service" ];
        bindsTo = [ "agency-display@%i.service" ];
        environment = {
          DISPLAY = ":%i";
          XDG_RUNTIME_DIR = "/run/agency-selkies/%i";
        };
        serviceConfig = {
          RuntimeDirectory = "agency-selkies/%i";
          RuntimeDirectoryMode = "0700";
        };
      };

  # Starts desktops :1 to :count at boot.
  systemd.targets.agency-desktops = {
    description = "The virtual desktops chosen in settings.nix";
    wantedBy = [ "multi-user.target" ];
    wants = map (n: "agency-desktop@${toString n}.target") (lib.range 1 count);
  };

  environment.systemPackages = with pkgs; [
    gui
    xterm
    xdotool
    scrot
    xclip
    wmctrl
    imagemagick
  ];

  fonts.packages = with pkgs; [
    dejavu_fonts
    noto-fonts
    noto-fonts-color-emoji
  ];
}
