# Disk layout. The installer erases settings.disk and creates:
#
#   ESP   1 GB    /boot    (unencrypted, holds the boot loader and kernels)
#   luks  rest    encrypted; unlocked by the TPM chip at boot
#     btrfs
#       @root  /
#       @home  /home
#       @nix   /nix
#
# btrfs gives cheap snapshots and instant copies (`cp --reflink`), which
# agents use for throwaway work trees.
{ settings, ... }:
let
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = settings.disk;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # Only used while installing. The installer creates this throwaway
            # key, enrols the TPM and a recovery key, then deletes it.
            passwordFile = "/tmp/agency-luks.key";
            settings = {
              allowDiscards = true;
              crypttabExtraOpts = [ "tpm2-device=auto" ];
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  inherit mountOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  inherit mountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  inherit mountOptions;
                };
              };
            };
          };
        };
      };
    };
  };
}
