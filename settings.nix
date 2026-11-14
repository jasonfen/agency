# Every value that differs from one machine to the next lives in this file.
#
# The installer's setup wizard asks for most of these and rewrites the
# `githubUser` and `apps` lines on the installed machine, so keep each of
# those two on a single line.
{
  # Network name of the machine. It is reachable as <hostName>.local on the
  # LAN and as <hostName> on your tailnet.
  hostName = "agency";

  # The account agents (and you) log in as. It has passwordless sudo.
  user = "agent";

  timeZone = "UTC";

  # GitHub account whose public SSH keys can log in. Empty: the wizard asks.
  githubUser = "";

  # Extra SSH public keys, one string per key. Public keys are safe to commit.
  sshKeys = [ ];

  # Optional software, by id from apps.nix. The wizard starts from this list.
  apps = [ "chromium" "docker" ];

  # Size of the virtual desktop agents use for GUI apps.
  desktopGeometry = "1280x800";

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
