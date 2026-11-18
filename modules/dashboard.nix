# The web dashboard, over Tailscale only: status, updates, desktops, a web
# terminal, sign-ins, apps, secrets. dashboard/server.py serves it on
# 127.0.0.1:7380 as the agent account, and `tailscale serve` puts it on the
# tailnet at https://<hostName>.<tailnet>.ts.net (or http:// when the tailnet
# has HTTPS certificates off). The address is in /run/agency/dashboard-url.
#
# Only the machine's owner on Tailscale, and the logins in `dashboardUsers`
# in settings.nix, get in: `tailscale serve` tells the server who is asking.
#
# The web terminal is ttyd on 127.0.0.1:7381. The dashboard passes /terminal
# to it after the same login check.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  port = 7380;
  terminalPort = 7381;
  tailscale = config.services.tailscale.package;

  # The agents with a sign-in of their own: the catalog entries with an
  # `account` (apps.nix). The dashboard lists them under Accounts, and
  # agency-signin runs their sign-in in its terminal.
  catalog = import ../apps.nix { inherit pkgs settings; };
  accountApps = builtins.filter (app: app ? account) catalog;
  accounts = pkgs.writeText "agency-accounts.json" (
    builtins.toJSON (
      map (app: {
        inherit (app) id label;
        inherit (app.account) program;
        signedIn = app.account.signedIn or null;
        check = app.account.check or null;
      }) accountApps
    )
  );

  # `agency-signin <id>`: sign GitHub, or one agent from the catalog, in.
  # Only these.
  signin = pkgs.writeShellScriptBin "agency-signin" ''
    need() {
      if ! command -v "$1" >/dev/null; then
        echo "$2 is not installed. Add it in the dashboard under Apps, or: agency apps add $3"
        exit 1
      fi
    }
    case "''${1:-}" in
      github)
        gh auth login --hostname github.com --git-protocol https --web && gh auth setup-git && agency-git-identity ;;
    ${lib.concatMapStrings (app: ''
      ${app.id})
        need ${lib.escapeShellArgs [ app.account.program app.label app.id ]}
        echo "Signing in to ${app.label}."
        ${app.account.signin} ;;
    '') accountApps}
      *)
        echo "usage: agency-signin github|${lib.concatMapStringsSep "|" (app: app.id) accountApps}" >&2
        exit 2 ;;
    esac
  '';

  # What ttyd runs for each browser tab: the shared tmux session, or a
  # sign-in first when the dashboard asks for one (?arg=<tool>).
  terminal = pkgs.writeShellScript "agency-terminal" ''
    cd "$HOME"
    if [ -n "''${1:-}" ]; then
      exec "''${SHELL:-bash}" -l -c 'agency-signin "$1"; echo; read -r -p "Press Enter for a shell. " _; exec tmux new -A -s main' agency-terminal "$1"
    fi
    exec "''${SHELL:-bash}" -l -c 'exec tmux new -A -s main'
  '';

  ttyd = pkgs.writeShellScript "agency-ttyd" ''
    exec ${pkgs.ttyd}/bin/ttyd ${
      lib.escapeShellArgs [
        "--interface"
        "127.0.0.1"
        "--port"
        (toString terminalPort)
        "--base-path"
        "/terminal"
        # Only requests that came through `tailscale serve` (and so through
        # the dashboard's login check) carry this header.
        "--auth-header"
        "Tailscale-User-Login"
        "--writable"
        "--url-arg"
        "--client-option"
        "titleFixed=terminal"
        "--client-option"
        "disableLeaveAlert=true"
        "--client-option"
        "fontSize=14"
        "--client-option"
        ''theme={"background":"#101813","foreground":"#e6efe0","cursor":"#e6efe0"}''
      ]
    } ${terminal}
  '';

  # Put the dashboard on the tailnet. HTTPS needs certificates switched on
  # for the tailnet; if they are off, `tailscale serve` waits for that, so
  # give it 20 seconds and fall back to plain HTTP on port 80. Traffic on
  # the tailnet is encrypted by Tailscale either way.
  serve = pkgs.writeShellScript "agency-dashboard-serve" ''
    set -u
    url_file=/run/agency/dashboard-url
    mkdir -p /run/agency
    status=$(tailscale status --json 2>/dev/null || true)
    name=$(printf '%s' "$status" | jq -r '.Self.DNSName // empty' | sed 's/\.$//')
    if [ "$(printf '%s' "$status" | jq -r '.BackendState // empty')" != Running ] || [ -z "$name" ]; then
      rm -f "$url_file"
      echo "Tailscale is not connected yet; trying again later."
      exit 0
    fi

    # Already served? Then there is nothing to do, except to try HTTPS
    # again once an hour in case it was switched on.
    if tailscale serve status --json 2>/dev/null | grep -q '127.0.0.1:${toString port}'; then
      if grep -qx "https://$name" "$url_file" 2>/dev/null; then exit 0; fi
      if grep -qx "http://$name" "$url_file" 2>/dev/null && [ -n "$(find "$url_file" -mmin -60)" ]; then exit 0; fi
    fi

    if timeout 20 tailscale serve --bg --yes ${toString port}; then
      url="https://$name"
    elif timeout 20 tailscale serve --bg --yes --http=80 ${toString port}; then
      url="http://$name"
    else
      rm -f "$url_file"
      exit 1
    fi
    printf '%s\n' "$url" > "$url_file.tmp"
    mv "$url_file.tmp" "$url_file"
    echo "The dashboard is at $url"
  '';
in
{
  systemd.services.agency-dashboard = {
    description = "agency web dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # Everything on the system PATH, so it finds `agency`, gh and sudo.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
      tailscale
      pkgs.git
      pkgs.scrot
      pkgs.wmctrl
      pkgs.qrencode
    ];
    environment = {
      AGENCY_UI = "${../dashboard/ui}";
      AGENCY_FONTS = "${../installer/ui/fonts}";
      AGENCY_ACCOUNTS = "${accounts}";
      AGENCY_USER = settings.user;
      # Where `bun add -g` and `npm install -g` put agent CLIs (see
      # modules/agents.nix).
      BUN_INSTALL = "${config.users.users.${settings.user}.home}/.bun";
      NPM_CONFIG_PREFIX = "${config.users.users.${settings.user}.home}/.npm-global";
      AGENCY_DASHBOARD_USERS = lib.concatStringsSep " " (settings.dashboardUsers or [ ]);
    };
    serviceConfig = {
      User = settings.user;
      ExecStart = "${pkgs.python3}/bin/python3 ${../dashboard/server.py}";
      Restart = "always";
      RestartSec = 2;
    };
  };

  systemd.services.agency-terminal = {
    description = "agency web terminal (ttyd)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    serviceConfig = {
      User = settings.user;
      ExecStart = ttyd;
      Restart = "always";
      RestartSec = 2;
    };
  };

  # Runs at boot and then every minute, so the dashboard appears soon after
  # Tailscale is connected, whenever that happens.
  systemd.services.agency-dashboard-serve = {
    description = "Put the agency dashboard on the tailnet";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "agency-dashboard.service"
    ];
    wants = [ "tailscaled.service" ];
    path = [
      tailscale
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = serve;
    };
  };
  systemd.timers.agency-dashboard-serve = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };

  environment.systemPackages = [ signin ];
}
