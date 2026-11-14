# Everything you are likely to change when adapting this repo to another
# machine lives in this one file.
{
  # Network name of the machine. It is reachable as <hostName>.local on the
  # LAN and as <hostName> on your tailnet.
  hostName = "agency";

  # The account agents (and you) log in as. It has passwordless sudo.
  user = "agent";

  timeZone = "UTC";

  # The disk the installer ERASES. Check with `lsblk` if unsure.
  disk = "/dev/nvme0n1";

  # Wipe guard. The installer only runs unattended on a machine whose DMI
  # vendor string contains this text (see /sys/class/dmi/id/sys_vendor).
  # On any other machine it stops and waits for a human.
  vendorMatch = "Micro-Star";

  # SSH access. At install time the installer downloads the public keys of
  # this GitHub account (https://github.com/<name>.keys). Set to "" to skip.
  githubUser = "makors";

  # Extra SSH public keys, one string per key. Public keys are safe to commit.
  sshKeys = [ ];

  # Size of the virtual desktop agents use for GUI apps.
  desktopGeometry = "1280x800";
}
