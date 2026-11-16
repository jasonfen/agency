# Weekly package updates: newer nixpkgs from the stable channel in flake.nix,
# built and switched to unattended. Only nixpkgs moves; the agency repo itself
# changes only when someone runs `agency update`. A failed build changes
# nothing, the machine never reboots on its own (a new kernel waits for the
# next reboot), and a clean, committed /etc/nixos is required so half-done
# work is never applied. `agency` shows the last result; `agency rollback`
# undoes an update.
{ settings, ... }:
{
  systemd.services.agency-auto-update = {
    description = "Update nixpkgs and rebuild the system";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ "/run/wrappers" "/run/current-system/sw" ];
    # The switch at the end of an update almost always changes this unit
    # (its PATH holds nixpkgs store paths), and switch-to-configuration
    # would then stop it mid-run: the new system is active but flake.lock
    # is never committed. NixOS's own system.autoUpgrade does the same.
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      User = settings.user;
      StateDirectory = "agency-auto-update";
      # `agency` is the system's own command, so updates use the version of
      # it that is running now.
      ExecStart = "/run/current-system/sw/bin/agency auto-update";
    };
    environment.HOME = "/home/${settings.user}";
  };

  systemd.timers.agency-auto-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      RandomizedDelaySec = "30min";
      Persistent = true; # catch up if the machine was off at that time
    };
  };
}
