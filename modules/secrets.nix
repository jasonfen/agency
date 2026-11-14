# Secrets: API keys and tokens for agents, kept encrypted in this repo at
# secrets/agency.sops.json. Add one with `agency secret set NAME`.
#
# The file is encrypted with sops to this machine's SSH host key (and to the
# ed25519 keys that can log in). At boot sops-nix decrypts each secret to
# /run/secrets/NAME, readable by the agent account only, and new shells get
# it as the environment variable $NAME.
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  file = ../secrets/agency.sops.json;
  # The names are not encrypted, so they can be read here. Only names that
  # are valid shell variables are used.
  names =
    if builtins.pathExists file then
      builtins.filter (n: n != "sops" && builtins.match "[A-Z_][A-Z0-9_]*" n != null) (
        builtins.attrNames (builtins.fromJSON (builtins.readFile file))
      )
    else
      [ ];
in
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    defaultSopsFormat = "json";
    defaultSopsFile = lib.mkIf (names != [ ]) file;
    secrets = lib.genAttrs names (_: {
      owner = settings.user;
    });
  };

  environment.extraInit = lib.concatMapStrings (name: ''
    if [ -r /run/secrets/${name} ]; then export ${name}="$(cat /run/secrets/${name})"; fi
  '') names;

  environment.systemPackages = [
    pkgs.sops
    pkgs.ssh-to-age
  ];
}
