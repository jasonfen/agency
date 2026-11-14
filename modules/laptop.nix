# This laptop is a server: lid closed, always on, battery as a built-in UPS.
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

  # Intel thermal management; this is a thin chassis running all day.
  services.thermald.enable = true;
}
