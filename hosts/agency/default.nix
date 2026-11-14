# The machine. Each import is one concern; read them in this order.
{ settings, ... }:
{
  imports = [
    ./hardware.nix # what the laptop is made of
    ./disko.nix # how the disk is laid out
    ../../modules/agents.nix # the agent account and its tools
    ../../modules/apps.nix # optional software chosen in settings.nix
    ../../modules/firstboot.nix # finishes the installer's choices on first boot
    ../../modules/remote.nix # how you and agents reach the machine
    ../../modules/desktop.nix # the virtual desktop for GUI apps
    ../../modules/laptop.nix # run lid-closed, never sleep
  ];

  # When empty, the name comes from /etc/hostname, which the installer
  # writes with the name chosen during setup.
  networking.hostName = settings.hostName;
  time.timeZone = settings.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

  # Boot: systemd-boot, with every past system kept as a boot menu entry.
  # If a change breaks the machine, pick an older entry at boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true; # needed for TPM disk unlock

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      settings.user
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nixpkgs.config.allowUnfree = true;

  # Do not change after install. It records which NixOS release first
  # created this machine's state; it is not the version you are running.
  system.stateVersion = "26.05";
}
