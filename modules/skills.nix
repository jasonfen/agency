# Keeps all skills in one place (~/.agents/skills) and tells the installed
# agent CLIs about this machine without anyone having to point them at
# AGENTS.md.
#
#   skills/           short guides an agent loads when a task needs one:
#                     computer use, changing the system, secrets
#   instructions      a few lines every session starts with, pointing at
#                     /etc/nixos/AGENTS.md
#   settings          Claude Code starts every session with Remote Control
#                     on, so a person can follow and steer it from
#                     claude.ai/code or the Claude app
#
# All skills — both agency's built-ins and any skills a person or agent adds —
# live in ~/.agents/skills and are symlinked into every installed agent CLI
# declared in apps.nix (chosen in settings.apps, or found on PATH). A skill
# added directly inside one agent's skills folder is moved into ~/.agents/skills
# and linked across the rest. A person's own files, overrides, and provider-
# private folders (like Claude Code's synced/ and .trash/) are left alone.
# A setting is added only when it is missing, so a person who turns it off
# keeps it off.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  home = config.users.users.${settings.user}.home;
  skills = ../skills;

  catalog = import ../apps.nix { inherit pkgs settings; };
  skillProviders = builtins.filter (app: app ? skills || app ? instructions) catalog;

  providersConfig = pkgs.writeText "agency-skill-providers.json" (
    builtins.toJSON {
      hub = ".agents/skills";
      providers = map (app: {
        inherit (app) id;
        program = app.account.program or (app.command or null);
        chosen = builtins.elem app.id settings.apps;
        skills = app.skills or null;
        instructions = app.instructions or null;
      }) skillProviders;
    }
  );

  instructions = pkgs.writeText "agency-instructions.md" ''
    # This machine

    You are on agency, a NixOS machine set up for AI agents. You have
    passwordless sudo. Before you change the system itself, read
    /etc/nixos/AGENTS.md. The `agency` command shows the state of the
    machine (`agency help` lists the rest). Skills live in ~/.agents/skills
    and are symlinked into every installed agent; skills named agency-*
    cover the desktop and computer use, system changes, and secrets.
  '';

  syncSkills = pkgs.writeShellScriptBin "agency-sync-skills" ''
    exec ${pkgs.python3}/bin/python3 ${../cli/sync_skills.py} \
      --config ${providersConfig} \
      --skills ${skills} \
      --instructions ${instructions} \
      "$@"
  '';

  watchPaths = [
    "${home}/.agents/skills"
    "${home}/.bun/bin"
    "${home}/.npm-global/bin"
    "${home}/.local/bin"
  ] ++ map (app: "${home}/${app.skills}") (builtins.filter (app: app ? skills) skillProviders);
in
{
  environment.systemPackages = [ syncSkills ];

  # Runs at boot and on every rebuild that changes skills or chosen apps.
  systemd.services.agency-skills = {
    description = "Sync skills and instructions into installed agent CLIs";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = settings.user;
      ExecStart = "${syncSkills}/bin/agency-sync-skills";
    };
  };

  # Triggered whenever a skill or agent CLI is added or removed.
  systemd.services.agency-skills-sync = {
    description = "Sync changed skills into installed agent CLIs";
    serviceConfig = {
      Type = "oneshot";
      User = settings.user;
      ExecStart = "${syncSkills}/bin/agency-sync-skills --wait";
    };
  };

  systemd.paths.agency-skills-sync = {
    description = "Watch agent skill folders and CLI bins for changes";
    wantedBy = [ "multi-user.target" ];
    after = [ "agency-skills.service" ];
    pathConfig = {
      Unit = "agency-skills-sync.service";
      PathChanged = watchPaths;
    };
  };

  # Fallback in case a directory is created first and SKILL.md is saved later.
  systemd.timers.agency-skills-sync = {
    description = "Periodically reconcile agent skill symlinks";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "5min";
    };
  };
}
