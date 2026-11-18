# Turns the ids in settings.apps into software, using the catalog in
# apps.nix.
#
# Entries of the `system` kind become system settings here. Entries of the
# `npm` kind are installed into the agent account with Bun, where they
# update themselves, so Nix cannot install them. Instead agency-npm-apps
# checks at boot, and after a rebuild that changes the list, that each
# chosen package is installed (by Bun, or by npm before Bun was the
# installer), and installs and sets up any that are missing. So a
# machine rebuilt from settings.nix gets them without the installer or
# `agency apps add`. It never removes anything: `agency apps remove` does.
# Watch it with: journalctl -u agency-npm-apps
#
# Entries with `installScript` are installed the same way, by
# agency-script-apps: at boot and after a rebuild it runs the maker's
# install script, as the agent, for each chosen tool whose command is not
# in ~/.local/bin. Installers like to add ~/.local/bin to PATH in the shell
# files; it is on PATH already (modules/agents.nix), so the shell files are
# put back as they were. Tools with `t3Agent` are added to T3 Code as that
# ACP agent, running the installed binary, so one sign-in covers both; an
# entry a person already set up in T3 is left as it is. It never removes
# anything; a removed tool's binary stays until deleted.
# Watch it with: journalctl -u agency-script-apps
#
# Entries of the `flatpak` kind turn on Flatpak (as the `flatpak` entry
# does), and agency-flatpak-apps installs them from Flathub, system-wide.
# The rebuild starts it, at boot it checks again, and `agency apps` waits
# for it, so it returns once the app is there. It also uninstalls the Flatpaks it installed that are
# no longer chosen, so it stays defined while any are left.
#
# Every Flatpak, these and any installed by hand, gets full access to the
# machine: a global override, written here, opens the sandbox. Change it
# here; `flatpak override` cannot, as the file is read-only.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  catalog = import ../apps.nix { inherit pkgs settings; };
  chosen = builtins.filter (app: builtins.elem app.id settings.apps) catalog;
  npmApps = builtins.filter (app: app ? npm) chosen;
  scriptApps = builtins.filter (app: app ? installScript) chosen;
  flatpakApps = builtins.filter (app: app ? flatpak) chosen;
  flatpakEntry = lib.findFirst (app: app.id == "flatpak") { } catalog;

  # Opens the sandbox of every Flatpak: all files, devices, sockets and
  # buses, as if the app were installed normally.
  fullAccess = pkgs.writeText "flatpak-overrides-global" ''
    [Context]
    shared=network;ipc;
    sockets=x11;wayland;pulseaudio;session-bus;system-bus;ssh-auth;pcsc;cups;gpg-agent;
    devices=all;
    features=devel;multiarch;bluetooth;canbus;per-app-dev-shm;
    filesystems=host;host-etc;
  '';

  # Flatpaks this service installed, one id per line, so it knows which
  # to remove when they are switched off.
  flatpakState = "/var/lib/agency/flatpak-apps";

  user = settings.user;
  home = config.users.users.${user}.home;

  # One line per app: the package, then the setup command (may be empty).
  ensure = lib.concatMapStrings (app: ''
    ensure ${lib.escapeShellArg app.npm} ${lib.escapeShellArg (app.setup or "")}
  '') npmApps;

  # One line per script app: its command, install script and T3 agent id.
  ensureScripts = lib.concatMapStrings (app: ''
    ensure ${lib.escapeShellArgs [ app.command app.installScript (app.t3Agent or "") ]}
  '') scriptApps;
  t3Chosen = builtins.elem "t3code" settings.apps;
in
{
  config = lib.mkMerge (
    map (app: app.system or { }) chosen
    ++ [
      (lib.mkIf (flatpakApps != [ ] && !(builtins.elem "flatpak" settings.apps)) (
        flatpakEntry.system or { }
      ))

      (lib.mkIf config.services.flatpak.enable {
        systemd.tmpfiles.rules = [ "L+ /var/lib/flatpak/overrides/global - - - - ${fullAccess}" ];
      })

      {
        systemd.services.agency-flatpak-apps = {
          description = "Install the Flathub apps chosen in settings.nix";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "sysinit.target"
          ];
          # Nothing to do with none chosen and none installed before.
          unitConfig.ConditionPathExists = lib.mkIf (flatpakApps == [ ]) flatpakState;
          # No default dependencies, so boot does not wait for a download.
          unitConfig.DefaultDependencies = false;
          conflicts = [ "shutdown.target" ];
          before = [ "shutdown.target" ];
          path = [
            pkgs.flatpak
            pkgs.curl
            pkgs.coreutils
            pkgs.gnugrep
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            want=(${lib.escapeShellArgs (map (app: app.flatpak) flatpakApps)})
            mkdir -p ${dirOf flatpakState}
            touch ${flatpakState}

            removed=
            while read -r id; do
              [ -n "$id" ] || continue
              if ! printf '%s\n' "''${want[@]}" | grep -qxF "$id"; then
                echo "Removing $id"
                flatpak uninstall --system --noninteractive "$id" || true
                removed=1
              fi
            done <${flatpakState}
            if [ -n "$removed" ]; then
              flatpak uninstall --system --noninteractive --unused || true
            fi

            missing=()
            for id in "''${want[@]}"; do
              flatpak info --system "$id" >/dev/null 2>&1 || missing+=("$id")
            done
            if [ "''${#missing[@]}" -gt 0 ]; then
              # Up to five minutes for the network, so a rebuild offline fails
              # rather than hangs.
              for _ in $(seq 60); do
                curl -fsS --max-time 5 -o /dev/null https://dl.flathub.org/repo/summary.idx && break
                sleep 5
              done
              flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
              echo "Installing ''${missing[*]}"
              flatpak install --system --noninteractive flathub "''${missing[@]}"
            fi

            printf '%s\n' "''${want[@]}" | grep -v '^$' >${flatpakState} || rm -f ${flatpakState}
          '';
        };
      }

      (lib.mkIf (npmApps != [ ]) {
        systemd.services.agency-npm-apps = {
          description = "Install the npm apps chosen in settings.nix";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "agency-firstboot.service"
          ];
          wants = [ "network-online.target" ];
          # On a fresh install, agency-firstboot does this itself.
          unitConfig.ConditionPathExists = "!/var/lib/agency/firstboot";
          path = [
            pkgs.nodejs_24
            pkgs.bun
            pkgs.curl
            pkgs.coreutils
            pkgs.util-linux
            pkgs.systemd
          ];
          serviceConfig = {
            # "exec", so boot does not wait for the installs. RemainAfterExit, so a
            # rebuild that changes the list runs it again.
            Type = "exec";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 60;
          };
          script = ''
            uid=$(id -u ${user})
            # as_user COMMAND: run COMMAND as the agent, with its user services.
            as_user() {
              runuser -u ${user} -- env HOME=${home} BUN_INSTALL=${home}/.bun \
                NPM_CONFIG_PREFIX=${home}/.npm-global \
                PATH=${home}/.bun/bin:${home}/.npm-global/bin:$PATH \
                XDG_RUNTIME_DIR=/run/user/$uid \
                DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
                ${pkgs.runtimeShell} -c "$1"
            }

            # ensure PACKAGE SETUP: install PACKAGE if missing, then run SETUP.
            online=
            ensure() {
              [ -e ${home}/.bun/install/global/node_modules/"$1" ] && return 0
              [ -e ${home}/.npm-global/lib/node_modules/"$1" ] && return 0
              if [ -z "$online" ]; then
                until curl -fsS --max-time 10 -o /dev/null https://registry.npmjs.org/; do
                  sleep 5
                done
                systemctl start user@$uid.service || true
                online=1
              fi
              echo "Installing $1"
              as_user "bun add -g --trust '$1'"
              if [ -n "$2" ]; then
                as_user "$2"
              fi
            }

            ${ensure}
          '';
        };
      })

      (lib.mkIf (scriptApps != [ ]) {
        systemd.services.agency-script-apps = {
          description = "Install the script-installed apps chosen in settings.nix";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "agency-firstboot.service"
            "agency-npm-apps.service"
          ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            bash
            curl
            wget
            coreutils
            diffutils
            gnutar
            gzip
            unzip
            gnugrep
            gnused
            findutils
            which
            jq
            glibc.bin # ldd, which installers use to tell glibc from musl
            util-linux
          ];
          serviceConfig = {
            Type = "exec";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 60;
          };
          script = ''
            as_user() {
              runuser -u ${user} -- env HOME=${home} \
                PATH=${home}/.local/bin:$PATH ${pkgs.runtimeShell} -c "$1"
            }
            shell_files=(.bashrc .profile .bash_profile .zshrc)

            # ensure COMMAND SCRIPT T3AGENT
            ensure() {
              if [ ! -x ${home}/.local/bin/"$1" ]; then
                until curl -fsS --max-time 10 -o /dev/null "$2"; do
                  sleep 5
                done
                saved=$(mktemp -d)
                for f in "''${shell_files[@]}"; do
                  [ -e ${home}/$f ] && cp -p ${home}/$f "$saved/$f"
                done
                echo "Installing $1 from $2"
                as_user "curl -fsSL '$2' | bash"
                for f in "''${shell_files[@]}"; do
                  if [ -e "$saved/$f" ]; then
                    cmp -s "$saved/$f" ${home}/$f || cp -p "$saved/$f" ${home}/$f
                  else
                    rm -f ${home}/$f
                  fi
                done
                rm -rf "$saved"
              fi
              [ -n "$3" ] && add_to_t3 "$3" ${home}/.local/bin/"$1"
              return 0
            }

            # add_to_t3 AGENT BINARY: T3 Code's settings, which it reloads
            # when they change. Only if T3 is chosen or has run.
            t3=${home}/.t3/userdata/settings.json
            add_to_t3() {
              [ -d ${home}/.t3 ] || ${lib.boolToString t3Chosen} || return 0
              as_user "mkdir -p ${home}/.t3/userdata && { [ -s $t3 ] || echo '{}' >$t3; }"
              jq -e --arg k "acp_$1" '.providerInstances[$k]' $t3 >/dev/null && return 0
              echo "Adding $1 to T3 Code"
              as_user "jq --arg k 'acp_$1' --arg a '$1' --arg c '$2' \
                '.providerInstances[\$k] = { driver: \"acpRegistry\", config: { agentId: \$a, commandPath: \$c } }' \
                $t3 >$t3.agency && mv $t3.agency $t3"
            }

            ${ensureScripts}
          '';
        };
      })
    ]
  );
}
