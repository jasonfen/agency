# The installer. Everything that changes the disk happens in this script.
#
# It has three front ends:
#   setup screen  the graphical screen (installer/ui) collects the answers
#                 and runs this script with them as options
#   text wizard   asks the same questions in the terminal; the fallback
#                 when the graphical screen cannot start
#   unattended    no questions; uses the values baked in from settings.nix
#
# In all three, every check and every question comes BEFORE the disk is
# touched.
#
# Options:
#   --unattended            no questions
#   --hostname NAME         what to call the machine
#   --github-user NAME      whose SSH keys to install
#   --disk /dev/NAME        which disk to erase
#   --apps "ID ID ..."      which apps from apps.nix to install
#   --tailscale-state FILE  a saved Tailscale sign-in to carry over
#   --signin-home DIR       a home folder with sign-ins (GitHub, agent CLIs)
#   --password-hash-file F  a crypt(3) hash for the console password
#                           to carry over to the agent account
#   --force                 skip the vendor and already-installed checks
#   --yes                   skip the 30 second countdown
#   --no-reboot             stop after installing; do not restart
#
# Filled in from settings.nix and apps.nix by installer/default.nix:
#   AGENCY_HOSTNAME AGENCY_USER AGENCY_UNATTENDED AGENCY_DISK AGENCY_VENDOR
#   AGENCY_GITHUB_USER   may be empty
#   AGENCY_SSH_KEYS      file with extra public keys
#   AGENCY_APPS          file, one app per line, tab-separated:
#                        id, preselected (0/1), kind (system/npm), npm name, label
#   AGENCY_BAKED_SYSTEM  ids of the system apps already in the prebuilt system
#   AGENCY_WIPE          script that partitions, formats and mounts the disk
#   AGENCY_SYSTEM        the prebuilt system
#   AGENCY_SOURCE        this repo, copied to /etc/nixos on the new machine

unattended=$AGENCY_UNATTENDED
force=0
disk=$AGENCY_DISK
gh_user=$AGENCY_GITHUB_USER
host=$AGENCY_HOSTNAME
apps_arg=""
apps_given=0
ts_state=""
signin_home=""
password_hash=""
countdown=1
reboot=1
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --unattended) unattended=1 ;;
    --force) force=1 ;;
    --disk)
      disk=${2:-}
      shift
      ;;
    --github-user)
      gh_user=${2:-}
      shift
      ;;
    --hostname)
      host=${2:-}
      shift
      ;;
    --apps)
      apps_arg=${2:-}
      apps_given=1
      shift
      ;;
    --tailscale-state)
      ts_state=${2:-}
      shift
      ;;
    --signin-home)
      signin_home=${2:-}
      shift
      ;;
    --password-hash-file)
      password_hash=$(cat "${2:-/dev/null}")
      shift
      ;;
    --yes) countdown=0 ;;
    --no-reboot) reboot=0 ;;
    *)
      echo "usage: agency-install [--unattended] [--github-user NAME] [--disk /dev/NAME] [--apps \"ID ...\"] [--force]"
      exit 2
      ;;
  esac
  if [ $# -gt 0 ]; then shift; fi
done

luks_part=/dev/disk/by-partlabel/disk-main-luks
luks_key=/tmp/agency-luks.key
stick=/dev/disk/by-label/AGENCY
work=/tmp/agency-setup
ts_dir=$work/tailscale
log=$work/install.log

# ------------------------------------------------------------- launcher ---
# The wizard runs as a child process. If it stops for any reason (a failed
# check, Cancel, Ctrl-C) the launcher offers to start again, so a mistake
# never leaves a dead screen.

if [ "$unattended" = 0 ] && [ "${AGENCY_STAGE:-}" != wizard ]; then
  trap : INT
  while true; do
    if AGENCY_STAGE=wizard "$0" "${args[@]}"; then exit 0; fi
    printf '\n'
    choice=$(gum choose --no-show-help --header "Setup stopped. Nothing is lost by starting again." \
      "Start again" "Open a shell" "Power off") || choice="Open a shell"
    case "$choice" in
      "Start again") ;;
      "Power off")
        systemctl poweroff
        sleep infinity
        ;;
      *)
        printf '\nType "exit" to come back to setup.\n'
        bash -l || true
        ;;
    esac
  done
fi

# -------------------------------------------------------------- helpers ---

say() { printf '\n[agency] %s\n' "$*"; }

note() { printf '%s\n' "$*" | fold -s -w 76; }

pause() { read -r -p "$1 " _ || true; }

# Stop before anything was changed.
stop() {
  if [ "$unattended" = 1 ]; then
    say "STOPPED: $*"
    say "Nothing on the disk was changed."
    say "For a shell press Alt+F2. To retry: sudo agency-install"
  else
    printf '\n'
    gum style --foreground 1 --bold "Setup can't continue"
    note "$*"
    printf '\n'
    pause "Press Enter."
  fi
  exit 1
}

# Start a wizard screen: clear, then a title. Plain ASCII only: the text
# console cannot draw box characters reliably.
screen() {
  printf '\033[2J\033[H'
  gum style --foreground 2 --bold "agency setup   $1"
  printf -- '----------------------------------------\n\n'
}

# Run a long command. The wizard shows a spinner and prints the command's
# output only if it fails; unattended mode lets the output scroll.
run() {
  local title=$1
  shift
  if [ "$unattended" = 1 ]; then
    say "$title"
    "$@"
  else
    gum spin --spinner line --show-error --title "$title" -- "$@"
  fi
}

mkdir -p "$work"

ts_pid=""
cleanup() { if [ -n "$ts_pid" ]; then kill "$ts_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT

# --------------------------------------------------- checks, no questions ---

[ "$(id -u)" = 0 ] || stop "The installer must run as root: sudo agency-install"
[ -d /sys/firmware/efi ] ||
  stop "This machine booted in legacy mode. Turn off legacy/CSM boot in the BIOS so it boots in UEFI mode."
[ "$(cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null || true)" = 2 ] ||
  stop "No TPM 2.0 chip was found. Turn it on in the BIOS; it is often called 'Security Device Support', 'Intel PTT' or 'AMD fTPM'."

if [ "$unattended" = 0 ]; then
  screen "welcome"
  note "agency turns this computer into one that AI agents run. They get full control of it and a desktop of their own, and you check in from your laptop or phone."
  printf '\n'
  note "Setup takes about ten minutes. Installing erases one disk. You choose which, and nothing is changed until you confirm at the end."
  printf '\n'
  pause "Press Enter to begin."
fi

# -------------------------------------------------------------- network ---

online() { curl -fsS --max-time 8 -o /dev/null https://github.com; }

wait_online() {
  for _ in $(seq "$1"); do
    if online; then return 0; fi
    sleep 2
  done
  return 1
}

wifi_setup() {
  nmcli device wifi rescan 2>/dev/null || true
  sleep 4
  mapfile -t ssids < <(nmcli -t -f SSID device wifi list 2>/dev/null | sed 's/\\:/:/g' | grep -v '^$' | sort -u)
  if [ "${#ssids[@]}" = 0 ]; then
    note "No Wi-Fi networks were found. This machine may need a network cable."
    pause "Press Enter."
    return 0
  fi
  local ssid pass
  ssid=$(gum choose --no-show-help --header "Wi-Fi network" "${ssids[@]}")
  pass=$(gum input --no-show-help --password --header "Password for $ssid (leave empty if it has none)" --placeholder "")
  if [ -n "$pass" ]; then
    nmcli device wifi connect "$ssid" password "$pass" || true
  else
    nmcli device wifi connect "$ssid" || true
  fi
}

if [ "$unattended" = 1 ]; then
  say "Waiting for the network ..."
  wait_online 150 || stop "no internet connection. Check the network cable."
else
  screen "1 of 5   network"
  note "Checking the internet connection ..."
  until wait_online 6; do
    screen "1 of 5   network"
    choice=$(gum choose --no-show-help --header "No internet connection yet. A network cable is the easiest fix." \
      "Check again" "Set up Wi-Fi")
    if [ "$choice" = "Set up Wi-Fi" ]; then wifi_setup; fi
  done
  # Online already (usually by cable). Wi-Fi is still worth offering: the
  # computer may be moved somewhere without a cable after setup.
  if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi &&
    ! nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^wifi:connected'; then
    screen "1 of 5   network"
    note "Connected to the internet."
    printf '\n'
    if gum confirm --no-show-help --default=false --affirmative "Join Wi-Fi" --negative "Skip" \
      "Join a Wi-Fi network too? Useful if this computer will run without a cable."; then
      wifi_setup
    fi
  fi
fi

# -------------------------------------------------------- who can log in ---

keys=$work/authorized_keys
cat "$AGENCY_SSH_KEYS" >"$keys"

# Append the public keys of a GitHub account. Succeeds if at least one came.
fetch_keys() {
  local fetched=$work/github.keys
  curl -fsS --max-time 15 "https://github.com/$1.keys" >"$fetched" || return 1
  grep -Eq '^(ssh-|ecdsa-|sk-)' "$fetched" || return 1
  cat "$fetched" >>"$keys"
}

valid_user() { [[ "$1" =~ ^[A-Za-z0-9-]{1,39}$ ]]; }
valid_host() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]]; }
host=${host:-agency}

if [ "$unattended" = 1 ]; then
  valid_host "$host" || stop "'$host' is not a valid machine name. Use lowercase letters, numbers and hyphens."
  if [ -n "$gh_user" ]; then
    valid_user "$gh_user" || stop "'$gh_user' is not a valid GitHub username."
    fetch_keys "$gh_user" || true
  fi
  grep -Eq '^(ssh-|ecdsa-|sk-)' "$keys" ||
    stop "no SSH public key available. Add one to the GitHub account, pass --github-user NAME, or set 'sshKeys' in settings.nix."
else
  while true; do
    screen "2 of 5   name and login"
    note "Give this computer a name. Use lowercase letters, numbers and hyphens."
    printf '\n'
    host=$(gum input --no-show-help --header "Name of this computer" --value "$host")
    if valid_host "$host"; then break; fi
    note "That name won't work."
    pause "Press Enter to try again."
  done
  while true; do
    screen "2 of 5   name and login"
    note "You log in over SSH with the keys already on your GitHub account, so there is no password to set."
    printf '\n'
    gh_user=$(gum input --no-show-help --header "GitHub username" --placeholder "your-username" --value "$gh_user")
    if ! valid_user "$gh_user"; then
      note "That doesn't look like a GitHub username."
    elif fetch_keys "$gh_user"; then
      note "Found $(grep -Ec '^(ssh-|ecdsa-|sk-)' "$work/github.keys") SSH key(s) for $gh_user."
      sleep 2
      break
    else
      note "No SSH keys were found for '$gh_user'. Add one at github.com/settings/keys, then try again."
    fi
    pause "Press Enter to try again."
  done
  while true; do
    screen "2 of 5   name and login"
    note "A password for this computer's own screen (Ctrl+Alt+F2). SSH still uses your keys."
    printf '\n'
    pw1=$(gum input --no-show-help --password --header "Password (8 or more characters)")
    pw2=$(gum input --no-show-help --password --header "Same password again")
    if [ "${#pw1}" -lt 8 ]; then
      note "That is shorter than 8 characters."
    elif [ "$pw1" != "$pw2" ]; then
      note "The two passwords are different."
    else
      password_hash=$(printf '%s\n' "$pw1" | openssl passwd -6 -stdin)
      unset pw1 pw2
      break
    fi
    pause "Press Enter to try again."
  done
fi

# ----------------------------------------------------------------- disk ---

# The USB stick we booted from must never be the target.
boot_disk=""
boot_part=$(findmnt -no SOURCE /iso 2>/dev/null || true)
if [ -n "$boot_part" ]; then
  boot_disk=$(lsblk -no PKNAME "$boot_part" 2>/dev/null | head -n1 || true)
fi

# Internal disks, best first: NVMe before SATA and anything else.
# Removable disks, USB disks and the boot stick are never candidates.
ranked_disks() {
  lsblk -dnbo NAME,SIZE,TYPE,RM,TRAN |
    awk -v skip="$boot_disk" \
      '$3 == "disk" && $4 == 0 && $5 != "usb" && $1 != skip && $1 !~ /^(zram|loop|ram)/ { print ($5 == "nvme" ? 0 : 1), "/dev/" $1 }' |
    sort -n
}

describe() { lsblk -dno NAME,SIZE,MODEL "$1" | tr -s ' '; }

mapfile -t ranked < <(ranked_disks)

if [ -z "$disk" ]; then
  if [ "$unattended" = 1 ]; then
    # Take the NVMe disk, or failing that the SATA disk. If there are
    # several of the best kind, stop: a wrong guess erases data.
    first=${ranked[0]:-}
    candidates=()
    for line in "${ranked[@]}"; do
      if [ "${line%% *}" = "${first%% *}" ]; then candidates+=("${line#* }"); fi
    done
    if [ "${#candidates[@]}" -gt 1 ]; then
      say "This machine has several disks of the same kind:"
      lsblk -do NAME,SIZE,MODEL,TRAN "${candidates[@]}"
      stop "choose one. Either run: sudo agency-install --unattended --disk /dev/NAME   or set 'disk' in settings.nix and rebuild the stick."
    fi
    disk=${candidates[0]:-}
  else
    [ "${#ranked[@]}" -gt 0 ] || stop "No internal disk was found."
    options=()
    for line in "${ranked[@]}"; do
      options+=("$(describe "${line#* }")|${line#* }")
    done
    screen "3 of 5   disk"
    note "Choose the disk to install on. Everything on it will be erased, but not yet: you confirm at the end."
    printf '\n'
    disk=$(gum choose --no-show-help --header "Disk" --label-delimiter "|" "${options[@]}")
  fi
fi
if [ -z "$disk" ] || [ ! -b "$disk" ]; then
  stop "No usable internal disk was found (looked for '${disk:-any}'). Run lsblk to see what is there."
fi
disk=$(readlink -f "$disk")
[ "$disk" != "/dev/$boot_disk" ] || stop "The target disk $disk is the USB stick itself."

# Is there an earlier install, and on which disk?
old_disk=""
if [ -e "$luks_part" ]; then
  old_disk=/dev/$(lsblk -no PKNAME "$(readlink -f "$luks_part")" | head -n1)
fi

if [ "$unattended" = 1 ] && [ "$force" = 0 ]; then
  if [ -n "$AGENCY_VENDOR" ]; then
    vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
    case "$vendor" in
      *"$AGENCY_VENDOR"*) ;;
      *) stop "this is a '$vendor' machine but the installer expects '$AGENCY_VENDOR'. If this really is the right machine, run: sudo agency-install --unattended --force" ;;
    esac
  fi
  [ -z "$old_disk" ] || stop "this machine already holds an install, on $old_disk. If you meant to boot it, remove the USB stick and reboot. To erase it and install to $disk, run: sudo agency-install --unattended --force"
fi

# An earlier install on a different disk must go: two installs carry the
# same partition labels and the machine could boot either.
clear_old=""
if [ -n "$old_disk" ] && [ "$old_disk" != "$disk" ]; then clear_old=$old_disk; fi

# ------------------------------------------------------------ Tailscale ---
# Sign in here, then carry the sign-in over to the installed system, so the
# machine is on the tailnet from its first start.

if [ "$unattended" = 0 ]; then
  screen "4 of 5   Tailscale"
  note "Tailscale lets you reach this machine from anywhere, and it is the only way in from outside your network. You sign in by scanning a QR code with your phone."
  printf '\n'
  if gum confirm --no-show-help --affirmative "Connect" --negative "Skip" "Connect to Tailscale now?"; then
    mkdir -p "$ts_dir"
    tailscaled --tun=userspace-networking --state="$ts_dir/tailscaled.state" \
      --socket="$ts_dir/sock" >"$ts_dir/log" 2>&1 &
    ts_pid=$!
    sleep 3
    printf '\n'
    note "Scan the code, sign in, and approve the device. This screen continues by itself."
    if tailscale --socket="$ts_dir/sock" up --qr --ssh --hostname="$host" --timeout=10m; then
      ts_state=$ts_dir/tailscaled.state
    else
      note "Tailscale was not connected. You can do it after the install with: sudo tailscale up --ssh"
      pause "Press Enter to continue."
    fi
    kill "$ts_pid" 2>/dev/null || true
    wait "$ts_pid" 2>/dev/null || true
    ts_pid=""
  fi
fi

ts_ok=0
if [ -n "$ts_state" ] && [ -f "$ts_state" ]; then ts_ok=1; fi

# ----------------------------------------------------------------- apps ---

app_ids=()
app_labels=()
preselected=()
declare -A app_kind app_npm
while IFS=$'\t' read -r id sel kind npm label; do
  app_ids+=("$id")
  app_labels+=("$label")
  app_kind[$id]=$kind
  app_npm[$id]=$npm
  if [ "$sel" = 1 ]; then preselected+=("$id"); fi
done <"$AGENCY_APPS"

chosen=("${preselected[@]}")
if [ "$apps_given" = 1 ]; then
  read -r -a chosen <<<"$apps_arg"
fi
if [ "$unattended" = 0 ]; then
  options=()
  selected=()
  for i in "${!app_ids[@]}"; do
    options+=("${app_labels[$i]}|${app_ids[$i]}")
    for id in "${preselected[@]}"; do
      if [ "$id" = "${app_ids[$i]}" ]; then selected+=("--selected=${app_labels[$i]}"); fi
    done
  done
  screen "5 of 5   apps"
  note "Choose what to install. Space switches an item on or off, Enter confirms. Anything else can be added later."
  printf '\n'
  picked=$(gum choose --no-show-help --no-limit --height 14 --header "Apps" \
    --cursor-prefix "[ ] " --selected-prefix "[x] " --unselected-prefix "[ ] " \
    --label-delimiter "|" "${selected[@]}" "${options[@]}")
  chosen=()
  while read -r id; do
    if [ -n "$id" ]; then chosen+=("$id"); fi
  done <<<"$picked"
fi

# Sort the choice into the two kinds, dropping any id not in the catalog.
picked_ids=("${chosen[@]}")
chosen=()
chosen_system=()
chosen_npm=()
for id in "${picked_ids[@]}"; do
  if [ "${app_kind[$id]:-}" = npm ]; then
    chosen_npm+=("${app_npm[$id]}")
  elif [ -n "${app_kind[$id]:-}" ]; then
    chosen_system+=("$id")
  else
    continue
  fi
  chosen+=("$id")
done
# Sorted ids, each followed by a space: the same form as AGENCY_BAKED_SYSTEM.
system_list=$(printf '%s\n' "${chosen_system[@]}" | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')

# ------------------------------------------------------------ last call ---

if [ "$unattended" = 1 ]; then
  say "ALL DATA on $(describe "$disk") will be ERASED."
  if [ -n "$clear_old" ]; then
    say "The earlier install on $(describe "$clear_old") will be ERASED too."
  fi
  if [ "$countdown" = 1 ]; then
    say "To cancel, hold the power button now."
    for i in $(seq 30 -1 1); do
      printf '\r[agency] erasing in %2d seconds ' "$i"
      sleep 1
    done
    printf '\n'
  fi
else
  screen "ready"
  printf 'Name          %s\n' "$host"
  printf 'Log in with   SSH keys of github.com/%s\n' "$gh_user"
  if [ "$ts_ok" = 1 ]; then
    printf 'Tailscale     connected\n'
  else
    printf 'Tailscale     not set up\n'
  fi
  printf 'Apps          %s\n' "${chosen[*]:-none}"
  printf 'Disk          %s\n\n' "$(describe "$disk")"
  note "Everything on that disk will be erased."
  if [ -n "$clear_old" ]; then
    note "The earlier install on $(describe "$clear_old") will be erased as well."
  fi
  printf '\n'
  if ! gum confirm --no-show-help --default=false --affirmative "Erase and install" --negative "Cancel" "Install now?"; then
    note "Cancelled. Nothing was changed."
    exit 1
  fi
  printf '\n'
fi

# -------------------------------------------------------------- install ---
# From here on the disk is being changed.

if [ -n "$clear_old" ]; then
  say "Clearing the earlier install on $clear_old ..."
  lsblk -lnpo NAME "$clear_old" | tail -n +2 | while read -r part; do wipefs -a "$part"; done
  wipefs -a "$clear_old"
  blockdev --rereadpt "$clear_old" || true
  udevadm settle
fi

# The disk layout refers to the target as /dev/agency-target.
ln -sfn "$disk" /dev/agency-target
(umask 077 && head -c 32 /dev/urandom | base64 -w0 >"$luks_key")

run "Partitioning and formatting the disk" "$AGENCY_WIPE" --yes-wipe-all-disks
run "Copying the system to disk (several minutes)" \
  nixos-install --system "$AGENCY_SYSTEM" --no-root-passwd --no-channel-copy

# Bind the disk encryption to this machine's TPM so it starts unattended,
# add a recovery key, then remove the throwaway install key.
say "Setting up disk encryption ..."
install -d -m 700 /mnt/root
if ! {
  systemd-cryptenroll --unlock-key-file="$luks_key" --tpm2-device=auto --tpm2-pcrs=7 "$luks_part" &&
    systemd-cryptenroll --unlock-key-file="$luks_key" --recovery-key --wipe-slot=password "$luks_part" \
      >/mnt/root/luks-recovery-key.txt
} 2>"$log"; then
  cat "$log"
  say "Disk encryption setup failed. The disk has been erased; start again to retry."
  pause "Press Enter."
  exit 1
fi
chmod 600 /mnt/root/luks-recovery-key.txt
rm -f "$luks_key"

# SSH keys, and a copy of this repo with the choices made above.
say "Finishing up ..."
install -D -m 644 "$keys" /mnt/etc/agency/authorized_keys
mkdir -p /mnt/etc/nixos
cp -rT "$AGENCY_SOURCE" /mnt/etc/nixos
chmod -R u+w /mnt/etc/nixos
apps_nix=""
for id in "${chosen[@]}"; do apps_nix+="\"$id\" "; done
sed -i -E \
  -e "s|^  hostName = .*|  hostName = \"$host\";|" \
  -e "s|^  githubUser = .*|  githubUser = \"$gh_user\";|" \
  -e "s|^  apps = .*|  apps = [ $apps_nix];|" \
  /mnt/etc/nixos/settings.nix

# Notes for the first start (see modules/firstboot.nix).
notes=/mnt/var/lib/agency/firstboot
install -d -m 755 /mnt/var/lib/agency
install -d -m 700 "$notes"
if [ "$system_list" != "$AGENCY_BAKED_SYSTEM" ]; then touch "$notes/rebuild"; fi

# The machine's name. A prebuilt system with no name of its own reads it
# from /etc/hostname; one with a different name baked in has to rebuild.
if [ -z "$AGENCY_HOSTNAME" ]; then
  printf '%s\n' "$host" >/mnt/etc/hostname
elif [ "$host" != "$AGENCY_HOSTNAME" ]; then
  touch "$notes/rebuild"
fi
if [ "${#chosen_npm[@]}" -gt 0 ]; then printf '%s\n' "${chosen_npm[@]}" >"$notes/npm-packages"; fi
# The console password, as a hash only. The first start sets it.
if [ -n "$password_hash" ]; then (umask 077 && printf '%s\n' "$password_hash" >"$notes/password-hash"); fi

# Sign-ins made on the setup screen: only the credential files, which the
# first start moves into the agent's home. Their contents are never shown.
if [ -n "$signin_home" ] && [ -d "$signin_home" ]; then
  carried=0
  for item in .config/gh .claude .claude.json .codex .local/share/opencode; do
    if [ -e "$signin_home/$item" ]; then
      mkdir -p "$notes/home/$(dirname "$item")"
      cp -a "$signin_home/$item" "$notes/home/$item"
      carried=1
    fi
  done
  if [ "$carried" = 1 ]; then
    chown -R root:root "$notes/home"
    chmod -R go-rwx "$notes/home"
    chmod 700 "$notes/home"
  fi
fi
# The commit this system was built from, so `agency update` knows where
# the machine's own changes start.
if [ -n "${AGENCY_REV:-}" ]; then printf '%s\n' "$AGENCY_REV" >/mnt/var/lib/agency/source-rev; fi

# Carry the Tailscale sign-in and any Wi-Fi network over to the new system.
if [ "$ts_ok" = 1 ]; then
  install -d -m 700 /mnt/var/lib/tailscale
  install -m 600 "$ts_state" /mnt/var/lib/tailscale/tailscaled.state
fi
if compgen -G "/etc/NetworkManager/system-connections/*" >/dev/null; then
  install -d -m 700 /mnt/etc/NetworkManager/system-connections
  cp -p /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/
fi

# Optional secrets stick: a second USB drive whose volume label is AGENCY.
if [ -b "$stick" ]; then
  mkdir -p /run/agency-stick
  if mount "$stick" /run/agency-stick; then
    if [ "$ts_ok" = 0 ] && [ -f /run/agency-stick/tailscale-authkey ]; then
      tr -d '[:space:]' </run/agency-stick/tailscale-authkey >/mnt/var/lib/agency/tailscale-authkey
      chmod 600 /mnt/var/lib/agency/tailscale-authkey
      say "Tailscale key copied; the machine joins your tailnet on first start."
    fi
    cp /mnt/root/luks-recovery-key.txt /run/agency-stick/luks-recovery-key.txt &&
      say "Disk recovery key saved to the AGENCY stick."
    umount /run/agency-stick || true
  fi
fi
sync

# ----------------------------------------------------------------- done ---

recovery=$(cat /mnt/root/luks-recovery-key.txt)

if [ "$unattended" = 1 ]; then
  say "Done. Disk recovery key (also in /root/luks-recovery-key.txt on the new system):"
  printf '%s\n' "$recovery"
  if [ "$reboot" = 0 ]; then exit 0; fi
  say "Remove the USB stick. Rebooting in 20 seconds."
  sleep 20
else
  screen "done"
  printf 'On the same network    ssh %s@%s.local\n' "$AGENCY_USER" "$host"
  if [ "$ts_ok" = 1 ]; then
    printf 'From anywhere          ssh %s@%s\n' "$AGENCY_USER" "$host"
  fi
  printf '\n'
  note "The apps you chose finish installing in the background after the first start. That can take ten minutes."
  printf '\n'
  note "Disk recovery key. The disk is encrypted. If this computer's hardware fails or its BIOS is updated, this key is the only way to get back in. Save it now; scanning the code copies it to your phone."
  printf '\n%s\n\n' "$recovery"
  qrencode -t UTF8 -m 2 "$recovery" || true
  printf '\n'
  pause "Remove the USB stick, then press Enter to restart."
fi
systemctl reboot
