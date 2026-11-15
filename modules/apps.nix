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

  user = settings.user;
  home = config.users.users.${user}.home;

  # One line per app: the package, then the setup command (may be empty).
  ensure = lib.concatMapStrings (app: ''
    ensure ${lib.escapeShellArg app.npm} ${lib.escapeShellArg (app.setup or "")}
  '') npmApps;
in
{
  config = lib.mkMerge (
    map (app: app.system or { }) chosen
    ++ [
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
    ]
  );
}
