# Treat the machine as a server: lid closed, always on. On a laptop the
# battery acts as a built-in UPS. Harmless on a desktop.
{ ... }:
{
  # Closing the lid does nothing.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Never sleep, whatever asks for it.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Turn the built-in screen off after two idle minutes.
  boot.kernelParams = [ "consoleblank=120" ];

  # Let the CPU clock up at once instead of easing into it. Agents run in
  # short bursts (a git status, a test, a compile) that finish before the
  # default "balance_performance" has ramped up: a git status after a pause
  # takes 2.4 ms instead of 8.3 ms. It costs about 0.6 W at idle. On CPUs
  # without the setting (older ones, VMs) this does nothing.
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - performance"
  ];
}
