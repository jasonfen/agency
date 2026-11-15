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
#   you:     https://<hostName>.<tailnet>.ts.net:6081/   desktop :1
#            (6082 is :2, ...; the dashboard links to each)
#
# Ports: Selkies serves display :N on 127.0.0.1:6080+N, and `tailscale
# serve` puts that on the tailnet with HTTPS at the same port number.
# HTTPS is not optional: Selkies decodes video with the browser's WebCodecs,
# which browsers only allow on https:// pages (and on localhost). The X
# server itself listens on no port at all.
#
# X11 is deliberate: it lets one program see and control another, which is
# what computer use needs and what Wayland forbids.
{
  config,
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
      --addr 127.0.0.1 --port $((6080 + $1)) \
      --enable-basic-auth false \
      --manual-resolution true --manual-width ${width} --manual-height ${height} \
      --audio-enabled false --microphone-enabled false \
      --gamepad-enabled false --webcam-enabled false \
      --printing-enabled false \
      --ui-title "Desktop :$1"
  '';

  # Put each desktop's Selkies on the tailnet at https://<name>:6080+N,
  # and take removed desktops off it. HTTPS needs certificates switched on
  # for the tailnet (as for the dashboard); without them it falls back to
  # http://, where the page loads but browsers refuse to decode the video.
  serve = pkgs.writeShellScript "agency-desktops-serve" ''
    set -u
    if [ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')" != Running ]; then
      echo "Tailscale is not connected yet; trying again later."
      exit 0
    fi
    served=$(tailscale serve status --json 2>/dev/null || echo '{}')
    is_served() { printf '%s' "$served" | jq -e --arg p "$1" '(.TCP // {})[$p] != null' >/dev/null; }
    for n in $(seq 1 ${toString count}); do
      port=$((6080 + n))
      is_served $port && continue
      if timeout 20 tailscale serve --bg --yes --https=$port http://127.0.0.1:$port; then
        echo "Desktop :$n is at https on port $port"
      elif timeout 20 tailscale serve --bg --yes --http=$port http://127.0.0.1:$port; then
        echo "Desktop :$n is at plain http on port $port: switch on HTTPS certificates for the tailnet, or its video will not play"
      else
        echo "Could not put desktop :$n on the tailnet"
      fi
    done
    for n in $(seq ${toString (count + 1)} 32); do
      port=$((6080 + n))
      if is_served $port; then
        tailscale serve --https=$port off 2>/dev/null || tailscale serve --http=$port off 2>/dev/null || true
      fi
    done
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

  # Browser access to the desktop. No password: it listens on localhost,
  # and only reaches the tailnet through `tailscale serve` (below). Each desktop gets its own runtime
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

  # Runs at boot, after every switch, and then every minute, so the
  # desktops appear on the tailnet soon after Tailscale is connected.
  systemd.services.agency-desktops-serve = {
    description = "Put the virtual desktops on the tailnet";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    restartTriggers = [ serve ];
    path = [
      config.services.tailscale.package
      pkgs.jq
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = serve;
    };
  };
  systemd.timers.agency-desktops-serve = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
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
