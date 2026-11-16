# Hardware settings that suit most x86-64 laptops and PCs, Intel or AMD.
# If something on your machine is not detected, compare with the output of
# `nixos-generate-config --no-filesystems --show-hardware-config`.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Boot: systemd-boot, with every past system kept as a boot menu entry.
  # If a change breaks the machine, pick an older entry at boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
  # The systemd initrd is needed for TPM disk unlock. From NixOS 26.11 it is
  # the only initrd, and setting the option is an error. (The option is still
  # declared there, so this has to check the release, not the option.)
  boot.initrd.systemd = lib.optionalAttrs (lib.versionOlder lib.trivial.release "26.11") {
    enable = true;
  };

  # Drivers needed before the disk is unlocked. The installer offers any
  # disk the stick's own (much larger) kernel set can see, so every kind of
  # disk controller it might pick has to be here too, or the installed
  # system cannot find its disk at boot. "vmd" covers Intel machines whose
  # firmware puts the NVMe drive in RAID mode.
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
    "sdhci_acpi" # eMMC on Bay Trail and Cherry Trail laptops
    "thunderbolt"
    "tpm_crb"
    "tpm_tis"
    # Server RAID and SAS cards, which also show up in rented machines.
    "megaraid_sas"
    "mpt3sas"
    # Virtual machines: Proxmox and QEMU/KVM (virtio), Hyper-V, VMware
    # (LSI Logic and PVSCSI) and Xen.
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "hv_vmbus"
    "hv_storvsc"
    "mptspi"
    "mptsas"
    "vmw_pvscsi"
    "xen_blkfront"
    # Keyboards, for typing the recovery key when the TPM does not unlock
    # the disk. PS/2 and USB keyboards are covered by NixOS's defaults; these
    # are Hyper-V's, laptops' I2C keyboards, and Surface keyboards (Laptop 3
    # and later), which sit behind the Surface's own controller.
    "hyperv_keyboard"
    "intel_lpss_pci"
    "i2c_hid_acpi"
    "surface_aggregator"
    "surface_aggregator_registry"
    "surface_aggregator_hub"
    "surface_hid_core"
    "surface_hid"
    "8250_dw"
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
  # software. Blacklisting nouveau avoids a class of boot problems. To use
  # the card, set hardware.nvidia with PRIME offload and drop this line.
  boot.blacklistedKernelModules = [ "nouveau" ];

  zramSwap.enable = true;
}
