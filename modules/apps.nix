# Turns the ids in settings.apps into system settings, using the catalog in
# apps.nix. Entries of the `npm` kind are not handled here; they are
# installed into the agent account by modules/firstboot.nix.
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  catalog = import ../apps.nix { inherit pkgs settings; };
  chosen = builtins.filter (app: builtins.elem app.id settings.apps) catalog;
in
{
  config = lib.mkMerge (map (app: app.system or { }) chosen);
}
