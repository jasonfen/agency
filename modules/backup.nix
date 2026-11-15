# Backups of the home folder with restic: every hour, incremental and
# deduplicated, so an agent's `rm -rf` or `git reset --hard` can be undone.
#
# By default the restic repository is on this disk, in /var/lib/agency/backup
# (root only). That undoes mistakes but does not survive a dead disk. Point
# `backupRepo` in settings.nix at somewhere else (s3:..., b2:..., rest:...,
# sftp:...) for that, and store its credentials with `agency secret set`
# under restic's own names (AWS_ACCESS_KEY_ID, B2_ACCOUNT_KEY, ...).
# `backupRepo = null` turns backups off.
#
# The repository password is made on first run and kept in
# /var/lib/agency/backup-password. `agency backup password` shows it; keep a
# copy off the machine, or an off-machine repository is no use after a disaster.
#
# `agency backup` lists snapshots, `agency backup restore PATH` brings a file
# or folder back, and `sudo restic-home ...` is restic itself, set up for this
# repository.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  repo = settings.backupRepo or "";
  enabled = repo != null;
  local = "/var/lib/agency/backup";
  passwordFile = "/var/lib/agency/backup-password";
  home = "/home/${settings.user}";

  # restic's own environment variables for remote repositories. Each one
  # stored as an agency secret is passed to restic.
  envNames = [
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_DEFAULT_REGION"
    "AWS_SESSION_TOKEN"
    "B2_ACCOUNT_ID"
    "B2_ACCOUNT_KEY"
    "AZURE_ACCOUNT_NAME"
    "AZURE_ACCOUNT_KEY"
    "AZURE_ACCOUNT_SAS"
    "GOOGLE_PROJECT_ID"
    "RESTIC_REST_USERNAME"
    "RESTIC_REST_PASSWORD"
  ];
  present = builtins.filter (n: config.sops.secrets ? ${n}) envNames;

  # How long snapshots are kept.
  keep = [
    "--keep-hourly 24"
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
in
lib.mkIf enabled {
  services.restic.backups.home = {
    repository = if repo == "" then local else repo;
    inherit passwordFile;
    environmentFile = lib.mkIf (present != [ ]) config.sops.templates."restic-env".path;
    initialize = true;
    paths = [ home ];
    # Whatever is downloaded or rebuilt again on its own.
    exclude = [
      "${home}/.cache"
      "${home}/.npm"
      "${home}/.npm-global"
      "${home}/.bun/install/cache"
      "${home}/.cargo/registry"
      "${home}/.rustup"
      "${home}/go/pkg/mod"
      "${home}/.local/share/Trash"
      "${home}/.local/share/containers"
      "${home}/.local/share/flatpak"
      "${home}/.local/state/nix"
      "${home}/.nix-profile"
      "node_modules"
      ".venv"
    ];
    extraBackupArgs = [
      "--exclude-caches" # folders with a CACHEDIR.TAG, such as Rust's target/
      "--one-file-system"
      "--retry-lock 1h"
      "--skip-if-unchanged"
    ];
    # Pruning is daily, below, not after every backup.
    pruneOpts = [ ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
    # Record the time of the last good backup for `agency`.
    backupCleanupCommand = ''
      if [ "$SERVICE_RESULT" = success ]; then date +%s > /var/lib/agency/backup-last; fi
    '';
  };

  sops.templates."restic-env" = lib.mkIf (present != [ ]) {
    content = lib.concatMapStrings (n: "${n}=${config.sops.placeholder.${n}}\n") present;
  };

  # Make the repository password once.
  systemd.services.agency-backup-password = {
    description = "Make the backup repository password";
    requiredBy = [ "restic-backups-home.service" ];
    before = [ "restic-backups-home.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${passwordFile} ]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -base64 32 > ${passwordFile}.new
        mv ${passwordFile}.new ${passwordFile}
      fi
    '';
  };

  systemd.services.restic-backups-home.serviceConfig = {
    Nice = 10;
    IOSchedulingClass = "idle";
  };

  # Drop old snapshots once a day.
  systemd.services.agency-backup-prune = {
    description = "Drop old home folder backups";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = "/run/current-system/sw/bin/restic-home --retry-lock 2h forget --prune ${lib.concatStringsSep " " keep}";
    };
  };
  systemd.timers.agency-backup-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = lib.optional (repo == "") "d ${local} 0700 root root -";
}
