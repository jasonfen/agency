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

  # ---- What a person sees on a desktop. Kept light: a wallpaper, a panel
  # (tint2) with launchers, open windows and a clock, and a right-click
  # menu. The panel takes the bottom 30 pixels; maximized windows stop
  # above it.

  # A terminal that looks better than xterm's defaults.
  terminal = pkgs.writeShellScriptBin "agency-terminal" ''
    cd "$HOME"
    exec ${pkgs.xterm}/bin/xterm -title Terminal -fa "DejaVu Sans Mono" -fs 11 \
      -bg "#1b1e25" -fg "#d8dae0" -bc -geometry 100x30 "$@"
  '';
  terminalDesktop = pkgs.makeDesktopItem {
    name = "agency-terminal";
    desktopName = "Terminal";
    exec = "agency-terminal";
    icon = "utilities-terminal";
  };

  # The panel's icons: four from Papirus, copied into a tiny theme so the
  # system doesn't carry all of Papirus (over 250 MB) for them. Icons it
  # lacks come from hicolor, where apps install their own.
  icons = pkgs.runCommand "agency-icons" { } ''
    dir=$out/share/icons/agency
    mkdir -p $dir/scalable/apps
    for icon in utilities-terminal system-file-manager chromium firefox; do
      cp ${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/22x22/apps/$icon.svg $dir/scalable/apps/
    done
    cat > $dir/index.theme <<'EOF'
    [Icon Theme]
    Name=agency
    Inherits=hicolor
    Directories=scalable/apps

    [scalable/apps]
    Size=22
    MinSize=16
    MaxSize=256
    Type=Scalable
    EOF
  '';

  # Programs a person may want, in launcher order, with how to start them
  # and the .desktop file the panel takes the icon from. Ones that are not
  # installed (Firefox, say) are left out when the desktop starts.
  apps = [
    { name = "Terminal"; command = "agency-terminal"; desktop = "agency-terminal.desktop"; }
    { name = "Files"; command = "pcmanfm"; desktop = "pcmanfm.desktop"; }
    { name = "Chromium"; command = "chromium"; desktop = "chromium-browser.desktop"; }
    { name = "Firefox"; command = "firefox"; desktop = "firefox.desktop"; }
  ];
  appLines = lib.concatMapStrings (a: "${a.name}|${a.command}|${a.desktop}\n") apps;
  appList = pkgs.writeText "agency-desktop-apps" appLines;

  # Openbox's right-click menu, made when it is opened.
  menu = pkgs.writeShellScript "agency-menu" ''
    echo '<openbox_pipe_menu>'
    while IFS='|' read -r name command desktop; do
      command -v "$command" >/dev/null || continue
      echo "<item label=\"$name\"><action name=\"Execute\"><command>$command</command></action></item>"
    done < ${appList}
    echo '<separator/>'
    echo '<menu id="client-list-combined-menu"/>'
    echo '</openbox_pipe_menu>'
  '';

  # Openbox's own settings, with one workspace instead of four (a person
  # could lose windows on the others) and the menu above.
  openboxConfig = pkgs.runCommand "agency-openbox-config" { } ''
    mkdir -p $out/openbox
    sed 's|<number>4</number>|<number>1</number>|' \
      ${pkgs.openbox}/etc/xdg/openbox/rc.xml > $out/openbox/rc.xml
    cat > $out/openbox/menu.xml <<'EOF'
    <openbox_menu xmlns="http://openbox.org/3.4/menu">
      <menu id="root-menu" label="agency" execute="${menu}"/>
    </openbox_menu>
    EOF
  '';

  # Draws the wallpaper, writes the panel's settings for the installed
  # apps, and runs the panel. $1 is the display number.
  panel = pkgs.writeShellScript "agency-panel" ''
    set -u
    dir=$RUNTIME_DIRECTORY
    font=${pkgs.dejavu_fonts}/share/fonts/truetype
    ${pkgs.imagemagick}/bin/magick -size ${settings.desktopGeometry} \
      gradient:'#2a3140'-'#14171d' \
      -gravity center \
      -font $font/DejaVuSans-Bold.ttf -pointsize 44 -fill '#ffffff30' \
      -annotate +0-24 "Desktop :$1" \
      -font $font/DejaVuSans.ttf -pointsize 15 -fill '#ffffff40' \
      -annotate +0+26 'Agents use this screen. Start an app from the panel below, or right-click.' \
      "$dir/wallpaper.png"
    ${pkgs.hsetroot}/bin/hsetroot -cover "$dir/wallpaper.png"

    launchers=""
    while IFS='|' read -r name command desktop; do
      command -v "$command" >/dev/null || continue
      for d in ${terminalDesktop}/share/applications /run/current-system/sw/share/applications; do
        if [ -e "$d/$desktop" ]; then
          launchers="$launchers"$'\n'"launcher_item_app = $d/$desktop"
          break
        fi
      done
    done < ${appList}

    cat > "$dir/tint2rc" <<EOF
    # 1: panel  2: active window  3: other windows
    rounded = 0
    border_width = 0
    background_color = #101318 92
    border_color = #000000 0
    rounded = 4
    border_width = 0
    background_color = #ffffff 20
    border_color = #000000 0
    rounded = 4
    border_width = 0
    background_color = #ffffff 7
    border_color = #000000 0

    panel_items = LTC
    panel_size = 100% 30
    panel_margin = 0 0
    panel_padding = 6 3 8
    panel_position = bottom center horizontal
    panel_layer = top
    panel_background_id = 1
    panel_dock = 0
    wm_menu = 1
    strut_policy = follow_size
    font_shadow = 0

    launcher_padding = 2 0 6
    launcher_background_id = 0
    launcher_icon_size = 22
    launcher_icon_theme = agency
    launcher_tooltip = 1
    $launchers

    taskbar_mode = single_desktop
    taskbar_padding = 6 0 4
    taskbar_background_id = 0
    taskbar_name = 0
    task_icon = 1
    task_text = 1
    task_centered = 0
    task_maximum_size = 220 24
    task_padding = 6 2 6
    task_font = DejaVu Sans 9
    task_font_color = #c9ccd4 100
    task_active_font_color = #ffffff 100
    task_background_id = 3
    task_active_background_id = 2
    task_iconified_font_color = #8a8f99 100
    task_iconified_background_id = 0
    mouse_left = toggle_iconify
    mouse_middle = close

    time1_format = %H:%M
    time1_font = DejaVu Sans Bold 9
    time2_format = %a %-d %b
    time2_font = DejaVu Sans 7
    clock_font_color = #c9ccd4 100
    clock_padding = 6 0
    clock_background_id = 0

    tooltip_show_timeout = 0.4
    tooltip_hide_timeout = 0.1
    tooltip_padding = 6 4
    tooltip_background_id = 1
    tooltip_font_color = #e6e8ee 100
    tooltip_font = DejaVu Sans 9
    EOF
    exec ${pkgs.tint2}/bin/tint2 -c "$dir/tint2rc"
  '';

  # Put each desktop's Selkies on the tailnet at https://<name>:6080+N,
  # and take removed desktops off it. HTTPS needs certificates switched on
  # for the tailnet (as for the dashboard); without them it falls back to
  # http://, where the page loads but browsers refuse to decode the video.
  serve = pkgs.writeShellScript "agency-desktops-serve" ''
    set -u
    status=$(tailscale status --json 2>/dev/null || echo '{}')
    name=$(printf '%s' "$status" | jq -r '.Self.DNSName // empty' | sed 's/\.$//')
    if [ "$(printf '%s' "$status" | jq -r '.BackendState // empty')" != Running ] || [ -z "$name" ]; then
      echo "Tailscale is not connected yet; trying again later."
      exit 0
    fi
    served=$(tailscale serve status --json 2>/dev/null || echo '{}')
    is_served() { printf '%s' "$served" | jq -e --arg p "$1" '(.TCP // {})[$p] != null' >/dev/null; }
    # Served under this machine's current name? After a rename the port
    # stays served under the old name only, and its HTTPS fails for the new.
    is_served_here() { printf '%s' "$served" | jq -e --arg k "$name:$1" '(.Web // {})[$k] != null' >/dev/null; }
    for n in $(seq 1 ${toString count}); do
      port=$((6080 + n))
      is_served_here $port && continue
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

  # Apps started from the panel or the menu see the system's programs,
  # icons and fonts, as they would from a shell.
  desktopPath = [
    "/run/wrappers"
    "/run/current-system/sw"
  ];
  desktopEnv = {
    DISPLAY = ":%i";
    XDG_DATA_DIRS = "/run/current-system/sw/share";
  };

  # One desktop is four services, started and stopped together.
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
      "agency-panel@%i.service"
    ];
  };

  # The display server, in memory only. Local programs reach it through its
  # socket in /tmp/.X11-unix; it listens on no network port.
  systemd.services."agency-display@" =
    part "Virtual desktop :%i (Xvfb)"
      "${pkgs.xorg-server}/bin/Xvfb :%i -screen 0 ${settings.desktopGeometry}x24 -nolisten tcp";

  # A window manager that only draws, moves and resizes windows.
  # Programs started from its menu are its children, so KillMode=process
  # lets them outlive a restart of the window manager.
  systemd.services."agency-wm@" =
    lib.recursiveUpdate (part "Window manager for desktop :%i (Openbox)" "${pkgs.openbox}/bin/openbox")
      {
        after = [ "agency-display@%i.service" ];
        bindsTo = [ "agency-display@%i.service" ];
        path = desktopPath;
        environment = desktopEnv // {
          XDG_CONFIG_DIRS = "${openboxConfig}";
        };
        serviceConfig = {
          KillMode = "process";
          WorkingDirectory = "~";
        };
      };

  # The panel at the bottom, and the wallpaper. The same goes for the apps
  # its launchers start.
  systemd.services."agency-panel@" =
    lib.recursiveUpdate (part "Panel and wallpaper for desktop :%i (tint2)" "${panel} %i")
      {
        after = [ "agency-wm@%i.service" ];
        bindsTo = [ "agency-display@%i.service" ];
        path = desktopPath;
        environment = desktopEnv;
        serviceConfig = {
          KillMode = "process";
          WorkingDirectory = "~";
          RuntimeDirectory = "agency-panel/%i";
        };
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
    terminal
    terminalDesktop
    pcmanfm
    icons
    adwaita-icon-theme # what pcmanfm's own buttons use
    hicolor-icon-theme
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
