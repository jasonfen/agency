# Everything you are likely to change when adapting this repo to another
# machine lives in this one file.
{
  # Network name of the machine. It is reachable as <hostName>.local on the
  # LAN and as <hostName> on your tailnet.
  hostName = "agency";

  # The account agents (and you) log in as. It has passwordless sudo.
  user = "agent";

  timeZone = "UTC";

  # The disk the installer ERASES. Leave empty to use the NVMe disk, or the
  # SATA disk if there is no NVMe. With two of the same kind the installer
  # stops and asks; name one here (ideally by /dev/disk/by-id/...) to avoid it.
  disk = "";

  # Optional wipe guard. If set, the installer only runs unattended on a
  # machine whose vendor string (/sys/class/dmi/id/sys_vendor) contains this
  # text, for example "LENOVO". Empty means it installs on whatever it boots.
  vendorMatch = "";

  # SSH access. At install time the installer downloads the public keys of
  # this GitHub account (https://github.com/<name>.keys). Set to "" to skip.
  githubUser = "makors";

  # Extra SSH public keys, one string per key. Public keys are safe to commit.
  sshKeys = [ ];

  # Size of the virtual desktop agents use for GUI apps.
  desktopGeometry = "1280x800";
}
