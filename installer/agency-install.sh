# Unattended installer. Runs automatically when the USB stick boots.
#
# Order matters: every check happens BEFORE the disk is touched, so a failed
# check leaves the machine exactly as it was.
#
# These variables are filled in from settings.nix by installer/default.nix:
#   AGENCY_DISK         disk to erase
#   AGENCY_VENDOR       wipe guard: required DMI vendor text
#   AGENCY_GITHUB_USER  GitHub account whose public SSH keys are installed
#   AGENCY_SSH_KEYS     file with extra public keys from settings.nix
#   AGENCY_WIPE         script that partitions, formats and mounts the disk
#   AGENCY_SYSTEM       the prebuilt system to install
#   AGENCY_SOURCE       this repo, copied to /etc/nixos on the new system

force=0
if [ "${1:-}" = "--force" ]; then force=1; fi

luks_part=/dev/disk/by-partlabel/disk-main-luks
luks_key=/tmp/agency-luks.key
stick=/dev/disk/by-label/AGENCY

say() { printf '\n[agency] %s\n' "$*"; }

stop() {
  say "STOPPED: $*"
  say "Nothing on the disk was changed."
  say "For a shell press Alt+F2. To retry: sudo agency-install"
  exit 1
}

# ---------------------------------------------------------------- checks ---

[ "$(id -u)" = 0 ] || stop "must run as root."
[ -d /sys/firmware/efi ] || stop "not booted in UEFI mode. Disable legacy/CSM boot in the BIOS."
[ -b "$AGENCY_DISK" ] || stop "target disk $AGENCY_DISK does not exist. Run lsblk and fix 'disk' in settings.nix."

boot_part=$(findmnt -no SOURCE /iso 2>/dev/null || true)
if [ -n "$boot_part" ]; then
  boot_disk=$(lsblk -no PKNAME "$boot_part" 2>/dev/null || true)
  [ "/dev/$boot_disk" != "$AGENCY_DISK" ] || stop "target disk $AGENCY_DISK is the USB stick itself."
fi

if [ "$force" = 0 ]; then
  vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
  case "$vendor" in
    *"$AGENCY_VENDOR"*) ;;
    *) stop "this is a '$vendor' machine but the installer expects '$AGENCY_VENDOR'. If this really is the right machine, run: sudo agency-install --force" ;;
  esac
  [ ! -e "$luks_part" ] || stop "this disk already holds an install. Remove the USB stick and reboot. To erase and reinstall anyway, run: sudo agency-install --force"
fi

[ "$(cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null || true)" = 2 ] ||
  stop "no TPM 2.0 chip found. Enable it in the BIOS (often 'Security Device Support' or 'Intel PTT')."

# SSH keys: without one nobody could log in to the finished machine.
keys=$(mktemp)
cat "$AGENCY_SSH_KEYS" >"$keys"
if [ -n "$AGENCY_GITHUB_USER" ]; then
  say "Waiting for the network to fetch SSH keys of github.com/$AGENCY_GITHUB_USER ..."
  for _ in $(seq 60); do
    if curl -fsS --max-time 10 "https://github.com/$AGENCY_GITHUB_USER.keys" >>"$keys"; then break; fi
    sleep 5
  done
fi
grep -Eq '^(ssh-|ecdsa-|sk-)' "$keys" ||
  stop "no SSH public key available. Add one to your GitHub account, or to 'sshKeys' in settings.nix, and check the network cable."

# ------------------------------------------------------------- last call ---

say "ALL DATA on $AGENCY_DISK ($(lsblk -dno MODEL,SIZE "$AGENCY_DISK" | tr -s ' ')) will be ERASED."
say "To cancel, hold the power button now."
for i in $(seq 30 -1 1); do
  printf '\r[agency] erasing in %2d seconds ' "$i"
  sleep 1
done
printf '\n'

# --------------------------------------------------------------- install ---

say "Partitioning and formatting $AGENCY_DISK ..."
(umask 077 && head -c 32 /dev/urandom | base64 -w0 >"$luks_key")
"$AGENCY_WIPE" --yes-wipe-all-disks

say "Copying the system to disk (several minutes) ..."
nixos-install --system "$AGENCY_SYSTEM" --no-root-passwd --no-channel-copy

say "Binding disk encryption to this machine's TPM ..."
systemd-cryptenroll --unlock-key-file="$luks_key" --tpm2-device=auto --tpm2-pcrs=7 "$luks_part"
# Add a recovery key, then remove the throwaway install key.
install -d -m 700 /mnt/root
systemd-cryptenroll --unlock-key-file="$luks_key" --recovery-key --wipe-slot=password "$luks_part" \
  >/mnt/root/luks-recovery-key.txt
chmod 600 /mnt/root/luks-recovery-key.txt
rm -f "$luks_key"

say "Installing SSH keys and a copy of this repo ..."
install -D -m 644 "$keys" /mnt/etc/agency/authorized_keys
mkdir -p /mnt/etc/nixos
cp -rT "$AGENCY_SOURCE" /mnt/etc/nixos
chmod -R u+w /mnt/etc/nixos

# Optional secrets stick: a second USB drive whose volume label is AGENCY.
if [ -b "$stick" ]; then
  say "Found the AGENCY secrets stick."
  mkdir -p /run/agency-stick
  if mount "$stick" /run/agency-stick; then
    if [ -f /run/agency-stick/tailscale-authkey ]; then
      install -d -m 700 /mnt/var/lib/agency
      tr -d '[:space:]' </run/agency-stick/tailscale-authkey >/mnt/var/lib/agency/tailscale-authkey
      chmod 600 /mnt/var/lib/agency/tailscale-authkey
      say "Tailscale key copied; the machine joins your tailnet on first boot."
    fi
    cp /mnt/root/luks-recovery-key.txt /run/agency-stick/luks-recovery-key.txt &&
      say "Disk recovery key saved to the stick as luks-recovery-key.txt."
    umount /run/agency-stick || true
  fi
fi

sync
say "Done. Disk recovery key (also in /root/luks-recovery-key.txt on the new system):"
cat /mnt/root/luks-recovery-key.txt
printf '\n'
say "Remove the USB stick. Rebooting in 20 seconds."
sleep 20
systemctl reboot
