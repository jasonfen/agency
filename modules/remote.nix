# How you and agents reach the machine. There is no monitor or keyboard in
# normal use; everything comes in over SSH or Tailscale.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  authKeyFile = "/var/lib/agency/tailscale-authkey";
in
{
  networking.networkmanager.enable = true;

  # SSH: keys only.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
    # The installer writes the keys it downloads from GitHub here.
    authorizedKeysFiles = [ "/etc/agency/authorized_keys" ];
  };

  # Makes the machine answer to <hostName>.local on the LAN, so you can find
  # it before Tailscale is set up.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  }
  # NixOS 26.11 moved publishing under `settings`, where it is off by default.
  // (
    if lib.versionOlder lib.trivial.release "26.11" then
      {
        publish = {
          enable = true;
          addresses = true;
        };
      }
    else
      {
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
        };
      }
  );

  # Tailscale: the private network you use from anywhere. Everything arriving
  # over it is trusted; from the LAN only SSH is open.
  services.tailscale.enable = true;
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  # Optional zero-touch join. If the installer found a one-time key on the
  # secrets stick it left it at authKeyFile; use it once, then delete it.
  # Without a key, run `sudo tailscale up --ssh` over SSH instead.
  systemd.services.agency-tailscale-join = {
    description = "Join the tailnet with the one-time key from the install stick";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = authKeyFile;
    path = [ config.services.tailscale.package ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 10;
    };
    script = ''
      tailscale up --ssh --auth-key "file:${authKeyFile}"
      rm -f ${authKeyFile}
    '';
  };

  environment.systemPackages = [ pkgs.tailscale ];
}
