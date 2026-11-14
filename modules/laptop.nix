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
}
