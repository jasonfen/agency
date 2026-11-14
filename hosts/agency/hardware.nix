# Hardware: MSI GF63 Thin 11UC (Intel i7-11800H, Intel UHD + Nvidia RTX 3050).
# To port to another machine, replace this file with the output of
# `nixos-generate-config --no-filesystems --show-hardware-config`.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Drivers needed before the disk is unlocked. "vmd" covers laptops whose
  # firmware puts the NVMe drive behind Intel VMD (RAID mode).
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "vmd"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "tpm_crb"
    "tpm_tis"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # The Nvidia card is left unused: agents' desktops are software-rendered and
  # the Intel GPU drives the panel. Blacklisting nouveau avoids a class of
  # boot and suspend problems. See AGENTS.md for how to enable the card.
  boot.blacklistedKernelModules = [ "nouveau" ];

  zramSwap.enable = true;
}
