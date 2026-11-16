# Every value that differs from one machine to the next lives in this file.
#
# The installer's setup screen asks for most of these and rewrites the
# `hostName`, `keyboard`, `githubUser` and `apps` lines on the installed
# machine, so keep each of those four on a single line.
{
  # Name of the machine. It is reachable as <hostName>.local on the LAN and
  # as <hostName> on your tailnet. Empty: setup asks for one.
  hostName = "";

  # The account agents (and you) log in as. It has passwordless sudo.
  user = "agent";

  timeZone = "UTC";

  # Keyboard layout, by its XKB name ("us", "de", "fr", "gb" ...), for the
  # machine's own screen and the disk prompt at boot.
  keyboard = "us";

  # Which nixpkgs the system is built from. "stable" (nixos-26.05) only gets
  # fixes until the next release; "unstable" (nixos-unstable) has the newest
  # versions and occasionally breaks. `agency channel` switches it.
  channel = "stable";

  # GitHub account whose public SSH keys can log in. Empty: the wizard asks.
  githubUser = "";

  # Extra SSH public keys, one string per key. Public keys are safe to commit.
  sshKeys = [ ];

  # Optional software, by id from apps.nix. The wizard starts from this list.
  apps = [ "chromium" "docker" ];

  # Size of the virtual desktops agents use for GUI apps.
  desktopGeometry = "1280x800";

  # How many virtual desktops run (:1, :2, ...). Give each agent that uses
  # the GUI at the same time its own. `agency desktop add` changes this.
  desktops = 1;

  # Stop charging the battery at this percent, to keep it healthy on a
  # machine that is always plugged in. null: charge to 100%. Does nothing
  # on hardware without a charge limit. See modules/battery.nix.
  batteryChargeLimit = 80;

  # Where the hourly backups of the home folder go: a restic repository.
  # Empty: on this disk, which undoes mistakes but not a dead disk. For that,
  # use s3:..., b2:..., rest:... or sftp:... and store its keys with
  # `agency secret set`. null: no backups. See modules/backup.nix.
  backupRepo = "";

  # Tailscale logins, besides this machine's owner, that may use the web dashboard.
  dashboardUsers = [ ];

  # The repo this machine updates from with `agency update`. Point it at
  # your fork to update from there.
  repo = "https://github.com/makors/agency";

  # --- Unattended installs -------------------------------------------------
  # Set this to true in your own fork to skip the wizard: the stick then
  # installs with the values in this file and no questions. It needs
  # githubUser or sshKeys to be set.
  unattended = false;

  # The disk an unattended install ERASES. Empty: the NVMe disk, or the SATA
  # disk if there is no NVMe. Name one (ideally by /dev/disk/by-id/...) on
  # machines with two of the same kind.
  disk = "";

  # Optional guard for unattended installs. If set, the installer only runs
  # on a machine whose vendor string (/sys/class/dmi/id/sys_vendor) contains
  # this text, for example "LENOVO".
  vendorMatch = "";
}
