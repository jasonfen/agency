# Finishes what the installer started.
#
# The installer copies a prebuilt system to disk, which cannot include
# choices made in the setup wizard. It leaves notes in /var/lib/agency/firstboot
# and this service acts on them the first time the machine has a network:
#
#   rebuild        rebuild the system, because settings.nix was changed
#   npm-packages   tools to `npm install -g` for the agent account
#
# Each note is deleted once done, so a failed run retries only what is left.
# Watch it with: journalctl -fu agency-firstboot
{
  config,
  pkgs,
  settings,
  ...
}:
let
  notes = "/var/lib/agency/firstboot";
in
{
  systemd.services.agency-firstboot = {
    description = "Finish the setup chosen in the installer";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = notes;
    # A rebuild must not restart the service that is running it.
    restartIfChanged = false;
    stopIfChanged = false;
    path = [
      config.system.build.nixos-rebuild
      config.nix.package
      pkgs.git
      pkgs.curl
      pkgs.coreutils
      pkgs.util-linux
    ];
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 60;
      TimeoutStartSec = "infinity";
    };
    script = ''
      until curl -fsS --max-time 10 -o /dev/null https://cache.nixos.org/nix-cache-info; do
        sleep 5
      done

      if [ -e ${notes}/rebuild ]; then
        nixos-rebuild switch --flake /etc/nixos#${settings.hostName}
        rm -f ${notes}/rebuild
      fi

      if [ -s ${notes}/npm-packages ]; then
        runuser -l ${settings.user} -c "npm install -g $(tr '\n' ' ' <${notes}/npm-packages)"
      fi
      rm -f ${notes}/npm-packages

      rmdir ${notes}
    '';
  };
}
