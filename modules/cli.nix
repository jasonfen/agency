# The `agency` command (cli/agency.py): status, updates, apps, desktops,
# secrets and the disk recovery key. Run `agency help` on the machine.
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
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.git
              pkgs.sops
              pkgs.ssh-to-age
              pkgs.qrencode
              pkgs.nodejs_24
              config.nix.package
              config.system.build.nixos-rebuild
              config.services.tailscale.package
            ]
          }
      '';
in
{
  environment.systemPackages = [ agency ];
}
