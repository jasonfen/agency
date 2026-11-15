# Tells the agent CLIs about this machine without anyone having to point
# them at AGENTS.md.
#
#   skills/           short guides an agent loads when a task needs one:
#                     computer use, changing the system, secrets
#   instructions      a few lines every session starts with, pointing at
#                     /etc/nixos/AGENTS.md
#   settings          Claude Code starts every session with Remote Control
#                     on, so a person can follow and steer it from
#                     claude.ai/code or the Claude app
#
# They are linked into the places Claude Code, Codex, OpenCode and other
# agents look. A file a person put there is never replaced; links agency
# made are refreshed on every rebuild. A setting is added only when it is
# missing, so a person who turns it off keeps it off.
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

    # default FILE KEY VALUE: set KEY in the JSON file FILE, unless it is set.
    default() {
      mkdir -p "$(dirname "$1")"
      [ -s "$1" ] || echo '{}' >"$1"
      # Leave alone a file that has the key, or that jq cannot read.
      case "$(${pkgs.jq}/bin/jq --arg k "$2" 'has($k)' "$1" 2>/dev/null)" in
        false) ;;
        *) return 0 ;;
      esac
      tmp=$(mktemp "$1.XXXXXX")
      if ${pkgs.jq}/bin/jq --arg k "$2" --argjson v "$3" '.[$k] = $v' "$1" >"$tmp"; then
        mv "$tmp" "$1"
      else
        rm -f "$tmp"
      fi
    }
    default ${home}/.claude/settings.json remoteControlAtStartup true || true
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
