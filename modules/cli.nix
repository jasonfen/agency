# The `agency` command (cli/agency.py): status, updates, apps, desktops,
# secrets, backups, export and import, and the disk recovery key. Run `agency help` on the machine.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  agency =
    pkgs.runCommand "agency"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "agency";
      }
      ''
        makeWrapper ${pkgs.python3}/bin/python3 $out/bin/agency \
          --add-flags ${../cli/agency.py} \
          --set AGENCY_USER ${lib.escapeShellArg settings.user} \
          --set AGENCY_MIN_FREE_GB ${toString (settings.minFreeGB or 20)} \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.git
              pkgs.sops
              pkgs.age
              pkgs.gnutar
              pkgs.zstd
              pkgs.ssh-to-age
              pkgs.qrencode
              pkgs.nodejs_24
              pkgs.bun
              config.nix.package
              config.system.build.nixos-rebuild
              config.services.tailscale.package
            ]
          }
      '';
in
{
  environment.systemPackages = [ agency ];

  # agency's state folder is readable by the agent account; the private
  # parts inside it (first-boot notes, a Tailscale key) keep their own modes.
  systemd.tmpfiles.rules = [ "d /var/lib/agency 0755 root root -" ];
}
