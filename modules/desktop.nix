# The virtual desktop. It is display :1, it exists only in memory, and it is
# where every GUI app runs. Agents drive it with xdotool and screenshots; you
# watch or take over from a browser.
#
#   agents:  gui chromium            start an app on the desktop
#            DISPLAY=:1 xdotool ...  click and type
#            DISPLAY=:1 scrot x.png  screenshot
#   you:     http://<hostName>:6081/vnc.html   (over Tailscale only)
#
# X11 is deliberate: it lets one program see and control another, which is
# what computer use needs and what Wayland forbids.
{ pkgs, settings, ... }:
let
  display = ":1";
  vncPort = 5901;
  webPort = 6081;

  # `gui <command>`: run a program on the virtual desktop, detached.
  gui = pkgs.writeShellScriptBin "gui" ''
    export DISPLAY=${display}
    exec ${pkgs.util-linux}/bin/setsid -f "$@" >/dev/null 2>&1
  '';

  service = extra: {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = settings.user;
      Restart = "always";
      RestartSec = 2;
    }
    // extra;
  };
in
{
  # The display server. No password: it only listens on localhost, and the
  # web viewer below is reachable over Tailscale only (see remote.nix).
  systemd.services.agency-display = {
    description = "Virtual desktop ${display} (Xvnc)";
  }
  // service {
    ExecStart = "${pkgs.tigervnc}/bin/Xvnc ${display} -geometry ${settings.desktopGeometry} -depth 24 -SecurityTypes None -localhost -AlwaysShared";
  };

  # A window manager that only draws, moves and resizes windows.
  systemd.services.agency-wm = {
    description = "Window manager for the virtual desktop (Openbox)";
    after = [ "agency-display.service" ];
    bindsTo = [ "agency-display.service" ];
    environment.DISPLAY = display;
  }
  // service {
    ExecStart = "${pkgs.openbox}/bin/openbox";
  };

  # Web viewer for the desktop.
  systemd.services.agency-novnc = {
    description = "Browser access to the virtual desktop (noVNC)";
    after = [ "agency-display.service" ];
  }
  // service {
    ExecStart = "${pkgs.novnc}/bin/novnc --listen ${toString webPort} --vnc localhost:${toString vncPort}";
  };

  environment.systemPackages = with pkgs; [
    gui
    chromium
    xterm
    xdotool
    scrot
    xclip
  ];

  fonts.packages = with pkgs; [
    dejavu_fonts
    noto-fonts
    noto-fonts-color-emoji
  ];
}
