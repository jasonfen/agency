# Hardware settings that suit most x86-64 laptops and PCs, Intel or AMD.
# If something on your machine is not detected, compare with the output of
# `nixos-generate-config --no-filesystems --show-hardware-config`.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Drivers needed before the disk is unlocked. "vmd" covers Intel machines
  # whose firmware puts the NVMe drive in RAID mode.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "nvme"
    "vmd"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "sdhci_pci"
    "thunderbolt"
    "tpm_crb"
    "tpm_tis"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];

  # Each of these only takes effect on the matching CPU.
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # A discrete Nvidia card is left unused: agents' desktops are rendered in
  # software. Blacklisting nouveau avoids a class of boot problems. See
  # AGENTS.md for how to enable the card.
  boot.blacklistedKernelModules = [ "nouveau" ];

  zramSwap.enable = true;
}
