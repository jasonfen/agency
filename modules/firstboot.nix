# Finishes what the installer started.
#
# The installer copies a prebuilt system to disk, which cannot include
# choices made in the setup wizard. It leaves notes in /var/lib/agency/firstboot
# and this service acts on them the first time the machine has a network:
#
#   rebuild        rebuild the system, because settings.nix was changed
#   npm-packages   tools to `npm install -g` for the agent account
#   password-hash  the console password chosen in setup, as a hash
#   home/          sign-ins made on the setup screen (GitHub, agent CLIs),
#                  copied into the agent's home
#
# Then it links /etc/nixos to the agency repo on GitHub (`agency setup-repo`),
# so `agency update` works. If that fails, `agency update` does it later.
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
  user = settings.user;
  home = config.users.users.${settings.user}.home;
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
      pkgs.findutils
      pkgs.util-linux
      pkgs.shadow
      pkgs.nodejs_24
      pkgs.gh
    ];
    environment.HOME = "/root";
    serviceConfig = {
      # "exec", not "oneshot": boot does not wait for this to finish. A
      # oneshot that runs `nixos-rebuild switch` deadlocks, because the
      # switch waits for multi-user.target, which waits for the oneshot.
      Type = "exec";
      Restart = "on-failure";
      RestartSec = 60;
    };
    script = ''
      # The prebuilt system on the stick has no name, so this first boot
      # starts as "nixos" even though /etc/hostname has the chosen name.
      # Use the chosen name now, not only after the next restart.
      use_name() {
        name=$(tr -d '[:space:]' </etc/hostname 2>/dev/null || true)
        if [ -n "$name" ] && [ "$(cat /proc/sys/kernel/hostname)" != "$name" ]; then
          hostnamectl --transient hostname "$name" || true
          systemctl try-restart avahi-daemon.service || true
        fi
      }
      use_name

      # First, what needs no network: the console password and the
      # sign-ins made in setup.
      if [ -s ${notes}/password-hash ]; then
        usermod -p "$(cat ${notes}/password-hash)" ${settings.user}
        rm -f ${notes}/password-hash
      fi

      if [ -d ${notes}/home ]; then
        cp -a ${notes}/home/. ${home}/
        # Hand over everything that came, including folders cp created and
        # the home folder itself (cp -a gave it the copy's owner).
        (cd ${notes}/home && find . -print0) |
          (cd ${home} && xargs -0 -r chown -h ${user}:)
        if [ -e ${notes}/home/.config/gh/hosts.yml ]; then
          runuser -u ${user} -- env HOME=${home} gh auth setup-git || true
        fi
        rm -rf ${notes}/home
      fi

      until curl -fsS --max-time 10 -o /dev/null https://cache.nixos.org/nix-cache-info; do
        sleep 5
      done

      if [ -s ${notes}/npm-packages ]; then
        runuser -u ${user} -- env HOME=${home} NPM_CONFIG_PREFIX=${home}/.npm-global \
          npm install -g $(tr '\n' ' ' <${notes}/npm-packages)
      fi
      rm -f ${notes}/npm-packages

      runuser -l ${user} -c "agency setup-repo" || true

      # Last, so everything above is done even if this is interrupted.
      if [ -e ${notes}/rebuild ]; then
        systemctl reset-failed nixos-rebuild-switch-to-configuration.service 2>/dev/null || true
        nixos-rebuild switch --flake path:/etc/nixos#agency
        rm -f ${notes}/rebuild
        use_name
      fi

      rmdir ${notes}
    '';
  };
}
