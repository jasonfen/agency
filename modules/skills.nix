# Tells the agent CLIs about this machine without anyone having to point
# them at AGENTS.md.
#
#   skills/           short guides an agent loads when a task needs one:
#                     computer use, changing the system, secrets
#   instructions      a few lines every session starts with, pointing at
#                     /etc/nixos/AGENTS.md
#
# They are linked into the places Claude Code, Codex, OpenCode and other
# agents look. A file a person put there is never replaced; links agency
# made are refreshed on every rebuild.
{
  config,
  pkgs,
  settings,
  ...
}:
let
  home = config.users.users.${settings.user}.home;
  skills = ../skills;

  instructions = pkgs.writeText "agency-instructions.md" ''
    # This machine

    You are on agency, a NixOS machine set up for AI agents. You have
    passwordless sudo. Before you change the system itself, read
    /etc/nixos/AGENTS.md. The `agency` command shows the state of the
    machine (`agency help` lists the rest). Skills named agency-* cover
    the desktop and computer use, system changes, and secrets.
  '';

  link = pkgs.writeShellScript "agency-link-skills" ''
    set -eu
    # put SOURCE DEST: link DEST to SOURCE, unless DEST is a person's own file.
    put() {
      mkdir -p "$(dirname "$2")"
      if [ -L "$2" ]; then
        case "$(readlink "$2")" in /nix/store/*) ;; *) return 0 ;; esac
      elif [ -e "$2" ]; then
        return 0
      fi
      ln -sfn "$1" "$2"
    }
    for dir in ${home}/.claude/skills ${home}/.codex/skills ${home}/.agents/skills ${home}/.config/opencode/skills; do
      for skill in ${skills}/*/; do
        put "''${skill%/}" "$dir/$(basename "$skill")"
      done
    done
    put ${instructions} ${home}/.claude/CLAUDE.md
    put ${instructions} ${home}/.codex/AGENTS.md
    put ${instructions} ${home}/.config/opencode/AGENTS.md
  '';
in
{
  systemd.services.agency-skills = {
    description = "Link agency's skills and instructions into the agent CLIs";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = settings.user;
      ExecStart = link;
    };
  };
}
