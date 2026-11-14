# Optional software. The setup wizard shows this list, in this order, and
# `apps` in settings.nix records which ids are switched on.
#
# An entry is one of two kinds:
#   system = { ... }   NixOS settings, applied by a system rebuild
#   npm    = "name"    a command-line tool installed into the agent account
#                      with `npm install -g`, so it can update itself
#
# To add your own, copy an entry. Labels must not contain "|" or ",".
{ pkgs, settings }:
[
  # Agents
  {
    id = "claude-code";
    label = "Claude Code";
    npm = "@anthropic-ai/claude-code";
  }
  {
    id = "codex";
    label = "Codex CLI";
    npm = "@openai/codex";
  }
  {
    id = "opencode";
    label = "OpenCode";
    npm = "opencode-ai";
  }
  {
    id = "t3code";
    label = "T3 Code";
    npm = "t3";
  }

  # Apps and tools
  {
    id = "chromium";
    label = "Chromium browser";
    system.environment.systemPackages = [ pkgs.chromium ];
  }
  {
    id = "firefox";
    label = "Firefox browser";
    system.programs.firefox.enable = true;
  }
  {
    id = "docker";
    label = "Docker and distrobox";
    system = {
      virtualisation.docker.enable = true;
      users.users.${settings.user}.extraGroups = [ "docker" ];
      environment.systemPackages = [ pkgs.distrobox ];
    };
  }
  {
    id = "flatpak";
    label = "Flatpak";
    system = {
      services.flatpak.enable = true;
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.common.default = "*";
      };
    };
  }
  {
    id = "rust";
    label = "Rust toolchain";
    system.environment.systemPackages = [ pkgs.rustup ];
  }
  {
    id = "go";
    label = "Go toolchain";
    system.environment.systemPackages = [ pkgs.go ];
  }
]
