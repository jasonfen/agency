# Keeping the disk from filling up on its own.
#
# Every rebuild makes a new system generation, and nothing used to delete
# old ones, so each kept all its packages alive: a machine rebuilt often had
# 80 of them and tens of GB that only a manual `nix-collect-garbage -d`
# freed. Now:
#
# - Only the newest `keepGenerations` systems are kept (settings.nix). Older
#   ones are deleted at every activation of a new system, so a rebuild,
#   `agency update` and the weekly auto-update all clear them, and the boot
#   menu lists the same ones. A machine that already has many sheds them on
#   the first switch to a system with this module.
# - The packages only those generations used are freed by nix-gc.service:
#   started in the background after every `agency rebuild`/`update`, within
#   the hour after an activation deleted generations, and daily.
# - Below `minFreeGB` free, the hourly agency-disk-cleanup frees what it can
#   at once: unused packages, Docker build cache and dangling images, old
#   logs, and old backups (see backup.nix). Nix frees packages by itself
#   too when a build gets that low.
# - Backups on this disk over `backupMaxGB` are pruned within the hour, not
#   only at the nightly prune.
# - The journal is capped at 1 GB. Docker's dangling images and build cache
#   older than a week are removed. Stopped containers and volumes are kept:
#   they may hold an agent's work.
#
# The home folder's caches (~/.cache and the like) are left alone: tools keep
# whole installs there (browsers for Playwright, for example), and deleting
# part of one breaks it. Backups skip them already.
{
  config,
  options,
  lib,
  pkgs,
  settings,
  ...
}:
let
  keep = settings.keepGenerations or 5;
  minFree = settings.minFreeGB or 20;
  nix = config.nix.package;
  docker = config.virtualisation.docker.enable;

  # Backups on this disk, and their limit (see backup.nix), or null.
  backupMaxGB =
    if (settings.backupRepo or "") == "" then settings.backupMaxGB or 50 else null;
  gb = 1024 * 1024 * 1024;

  # Set when generations were deleted but their packages not freed yet.
  pending = "/var/lib/agency/disk-gc-pending";

  # Keep the newest `keep` generations of each profile given. Prints how
  # many it deleted. Nix never deletes the generation a profile points at.
  trim = pkgs.writeShellScript "agency-trim-generations" ''
    deleted=0
    for p in "$@"; do
      [ -L "$p" ] || continue
      before=$(ls -d "$p"-*-link 2>/dev/null | wc -l)
      ${nix}/bin/nix-env -p "$p" --delete-generations +${toString keep} >/dev/null 2>&1 || true
      after=$(ls -d "$p"-*-link 2>/dev/null | wc -l)
      deleted=$((deleted + before - after))
    done
    echo "$deleted"
  '';

  # The system profile, and the users' own (`nix profile`, `nix-env`).
  profiles = [
    "/nix/var/nix/profiles/system"
    "/nix/var/nix/profiles/per-user/*/profile"
    "/root/.local/state/nix/profiles/profile"
    "/home/*/.local/state/nix/profiles/profile"
  ];
in
{
  assertions = [
    {
      assertion = builtins.isInt keep && keep >= 2;
      message = "settings.nix: keepGenerations must be at least 2 (the running system and one to roll back to).";
    }
  ];

  # The boot menu lists the same generations that are kept.
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault keep;
  boot.loader.grub.configurationLimit = lib.mkDefault keep;

  # Runs on every switch (and at boot), after the boot menu is written, so
  # the menu and the kept generations match. Only symlinks are removed here;
  # freeing the packages takes minutes and is left to nix-gc.service.
  system.activationScripts.agency-trim-generations = ''
    n=$(${trim} /nix/var/nix/profiles/system)
    if [ "$n" -gt 0 ] 2>/dev/null; then
      echo "agency: deleted $n old system generation(s), keeping the newest ${toString keep}"
      mkdir -p /var/lib/agency && touch ${pending}
    fi
  '';

  # Garbage collection. No --delete-older-than: generations are kept by
  # count, so a machine rebuilt rarely still has one to roll back to.
  nix.gc = {
    automatic = true;
    dates = "daily";
    randomizedDelaySec = "1h";
    persistent = true;
    options = "";
  };
  systemd.services.nix-gc = {
    preStart = ''
      ${trim} ${lib.concatStringsSep " " profiles} >/dev/null
      rm -f ${pending}
    '';
    serviceConfig = {
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  # A build that finds less than minFreeGB free frees packages until there
  # is twice that.
  nix.settings.min-free = minFree * gb;
  nix.settings.max-free = 2 * minFree * gb;

  # (services.journald.settings replaces extraConfig in newer nixpkgs.)
  services.journald =
    if options.services.journald ? settings then
      { settings.Journal.SystemMaxUse = "1G"; }
    else
      { extraConfig = "SystemMaxUse=1G\n"; };

  # Hourly, and a few minutes after boot or after the switch that adds it:
  # free the packages of deleted generations, and everything that can go
  # when the disk is nearly full.
  systemd.services.agency-disk-cleanup = {
    description = "Free disk space";
    path = [
      pkgs.coreutils
      config.systemd.package
    ] ++ lib.optional docker config.virtualisation.docker.package;
    serviceConfig = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    script = ''
      avail() { df --output=avail -B1G /nix/store | tail -n 1 | tr -d ' '; }
      low=0
      if [ "$(avail)" -lt ${toString minFree} ]; then
        low=1
        echo "Only $(avail) GB free (minFreeGB is ${toString minFree}): clearing what can go."
      fi

      if [ -e ${pending} ] || [ $low = 1 ]; then
        systemctl start nix-gc.service || true
      fi

      ${lib.optionalString docker ''
        if systemctl -q is-active docker.service; then
          docker image prune -f --filter until=168h >/dev/null || true
          docker builder prune -f --filter until=168h >/dev/null || true
          if [ $low = 1 ]; then
            docker image prune -f >/dev/null || true
            docker builder prune -af >/dev/null || true
          fi
        fi
      ''}

      ${lib.optionalString (backupMaxGB != null) ''
        # Over the limit, say just after it was set: prune now, not tonight.
        backups=$(du -s -BG /var/lib/agency/backup 2>/dev/null | cut -f1 | tr -d G)
        if [ $low = 1 ] || [ "''${backups:-0}" -gt ${toString backupMaxGB} ]; then
          if systemctl cat agency-backup-prune.service >/dev/null 2>&1 \
            && ! systemctl -q is-active agency-backup-prune.service; then
            systemctl start --no-block agency-backup-prune.service || true
          fi
        fi
      ''}

      if [ $low = 1 ]; then
        journalctl --vacuum-size=200M --vacuum-time=7d || true
        echo "Now $(avail) GB free."
      fi
    '';
  };
  systemd.timers.agency-disk-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "5min";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "5min";
    };
  };
}
