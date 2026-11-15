# Stop charging the battery at batteryChargeLimit percent (settings.nix).
# The machine sits on the charger all the time, and a lithium battery held
# at 100% wears out fast; 80% keeps it healthy and still works as a UPS.
#
# Works with any laptop whose kernel driver exposes a charge limit:
#   - charge_control_end_threshold on the battery (ThinkPad, ASUS, MSI,
#     Dell, Framework, Huawei, LG, Samsung, System76, Toshiba, ...)
#   - charge_types "Long_Life" (some Dell and Lenovo models)
#   - conservation_mode (Lenovo IdeaPad; the firmware picks about 60-80%)
# On hardware with none of these it logs that and does nothing.
#
# Firmware can forget the limit, so it is set again whenever a battery
# appears and whenever the charger is plugged in or out.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  limit = settings.batteryChargeLimit or null;

  apply = pkgs.writeShellScript "agency-battery-limit" ''
    limit=${toString limit}
    set_value() { # file value
      [ "$(cat "$1" 2>/dev/null)" = "$2" ] && return 0
      echo "$2" > "$1" 2>/dev/null
    }

    found=0
    # Drivers that add the controls (msi-ec, thinkpad_acpi ...) can load a
    # little after the battery itself, so look a few times at boot.
    for try in 1 2 3 4 5 6 7 8 9 10; do
      for bat in /sys/class/power_supply/*; do
        [ "$(cat "$bat/type" 2>/dev/null)" = Battery ] || continue
        name=''${bat##*/}
        end=$bat/charge_control_end_threshold
        start=$bat/charge_control_start_threshold
        types=$bat/charge_types

        if [ -w "$end" ]; then
          found=1
          # Some drivers refuse an end below the start, so lower the start first.
          if [ -w "$start" ] && [ "$(cat "$start")" -ge "$limit" ] 2>/dev/null; then
            set_value "$start" $((limit > 10 ? limit - 10 : 0))
          fi
          if set_value "$end" "$limit"; then
            echo "$name: stops charging at $(cat "$end")%" \
              "$([ -r "$start" ] && echo "(starts again below $(cat "$start")%)")"
          else
            echo "$name: the driver refused a $limit% limit (it may only take certain values)" >&2
          fi
        elif [ -w "$types" ] && grep -q Long_Life "$types"; then
          found=1
          set_value "$types" Long_Life && echo "$name: charge type Long_Life (the firmware picks the limit)"
        fi
      done

      for mode in /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode; do
        [ -w "$mode" ] || continue
        found=1
        set_value "$mode" 1 && echo "conservation mode on (the firmware picks the limit, about 60-80%)"
      done

      [ "$found" = 1 ] && exit 0
      sleep 2
    done
    echo "No battery charge limit control found on this machine; nothing to do."
  '';
in
lib.mkIf (limit != null) {
  systemd.services.agency-battery-limit = {
    description = "Cap the battery charge at ${toString limit}%";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = apply;
    };
  };

  # Again when a battery appears or the charger is plugged in or out.
  services.udev.extraRules =
    let
      start = "RUN+=\"${pkgs.systemd}/bin/systemctl start --no-block agency-battery-limit.service\"";
    in
    ''
      SUBSYSTEM=="power_supply", ACTION=="add", ATTR{type}=="Battery", ${start}
      SUBSYSTEM=="power_supply", ACTION=="change", ATTR{type}=="Mains", ${start}
    '';
}
