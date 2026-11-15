# The virtual desktops. Each is an X11 display that exists only in memory,
# and it is where GUI apps run. Agents drive one with xdotool and
# screenshots; you watch or take over from a browser.
#
# Display :1 is always there. `desktops` in settings.nix sets how many run
# (:1, :2, ...), so agents that use the GUI at the same time each get their
# own. `agency desktop add` adds one.
#
#   agents:  gui chromium              start an app on :1 (or on $DISPLAY)
#            gui -d 2 chromium         start an app on :2
#            DISPLAY=:1 xdotool ...    click and type
#            DISPLAY=:1 scrot x.png    screenshot
#   you:     http://<hostName>:6081/vnc.html   desktop :1 (6082 is :2, ...)
#
# Ports: display :N is VNC port 5900+N on localhost, and web port 6080+N
# over Tailscale only (see remote.nix).
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

  # The web viewer's port depends on the display number.
  novnc = pkgs.writeShellScript "agency-novnc" ''
    exec ${pkgs.novnc}/bin/novnc --listen $((6080 + $1)) --vnc localhost:$((5900 + $1))
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
      "agency-novnc@%i.service"
    ];
  };

  # The display server. No password: it only listens on localhost, and the
  # web viewer is reachable over Tailscale only.
  systemd.services."agency-display@" =
    part "Virtual desktop :%i (Xvnc)"
      "${pkgs.tigervnc}/bin/Xvnc :%i -geometry ${settings.desktopGeometry} -depth 24 -SecurityTypes None -localhost -AlwaysShared";

  # A window manager that only draws, moves and resizes windows.
  systemd.services."agency-wm@" =
    lib.recursiveUpdate (part "Window manager for desktop :%i (Openbox)" "${pkgs.openbox}/bin/openbox")
      {
        after = [ "agency-display@%i.service" ];
        bindsTo = [ "agency-display@%i.service" ];
        environment.DISPLAY = ":%i";
      };

  # Web viewer for the desktop. Its start script needs `ps` and `hostname`.
  systemd.services."agency-novnc@" =
    lib.recursiveUpdate (part "Browser access to desktop :%i (noVNC)" "${novnc} %i")
      {
        after = [ "agency-display@%i.service" ];
        path = [
          pkgs.procps
          pkgs.inetutils # hostname
        ];
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
