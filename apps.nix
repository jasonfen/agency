# Optional software. The setup wizard shows this list, in this order, and
# `apps` in settings.nix records which ids are switched on.
#
# An entry is one of two kinds:
#   system = { ... }   NixOS settings, applied by a system rebuild
#   npm    = "name"    a command-line tool installed into the agent account
#                      with `npm install -g`, so it can update itself
#
# An npm entry may also have `setup`, a command the agent account runs once
# the package is installed, and `teardown`, run before it is removed.
#
# Every entry has a `group` and a one-line `description` for the
# dashboard's app catalog, and may have a logo: dashboard/ui/logos/<id>.svg.
#
# To add your own, copy an entry. Labels must not contain "|" or ",".
{ pkgs, settings }:
[
  # Agents
  {
    id = "claude-code";
    label = "Claude Code";
    group = "Agents";
    description = "Anthropic's coding agent for the terminal.";
    npm = "@anthropic-ai/claude-code";
  }
  {
    id = "codex";
    label = "Codex CLI";
    group = "Agents";
    description = "OpenAI's coding agent for the terminal.";
    npm = "@openai/codex";
  }
  {
    id = "opencode";
    label = "OpenCode";
    group = "Agents";
    description = "An open-source coding agent that works with many model providers.";
    npm = "opencode-ai";
  }
  {
    id = "t3code";
    label = "T3 Code";
    group = "Agents";
    description = "A web app for running and following coding agents. Runs as a service.";
    npm = "t3";
    # A systemd user service, so it survives reboots. T3 writes the unit
    # itself, because `t3 update` points it at each new version.
    setup = "t3 service install";
    teardown = "t3 service uninstall";
  }

  # Apps and tools
  {
    id = "chromium";
    label = "Chromium browser";
    group = "Browsers";
    description = "The browser agents use for the web and for computer use.";
    system.environment.systemPackages = [ pkgs.chromium ];
  }
  {
    id = "firefox";
    label = "Firefox browser";
    group = "Browsers";
    description = "A second browser, for sites that behave differently in Chromium.";
    system.programs.firefox.enable = true;
  }
  {
    id = "docker";
    label = "Docker and distrobox";
    group = "Development";
    description = "Containers for services and throwaway environments. Distrobox runs software that wants a normal distro.";
    system = {
      virtualisation.docker.enable = true;
      users.users.${settings.user}.extraGroups = [ "docker" ];
      environment.systemPackages = [ pkgs.distrobox ];
    };
  }
  {
    id = "flatpak";
    label = "Flatpak";
    group = "Development";
    description = "Desktop apps from Flathub that nixpkgs lacks.";
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
    group = "Development";
    description = "rustup, which installs cargo and rustc.";
    system.environment.systemPackages = [ pkgs.rustup ];
  }
  {
    id = "go";
    label = "Go toolchain";
    group = "Development";
    description = "The Go compiler and tools.";
    system.environment.systemPackages = [ pkgs.go ];
  }
  {
    id = "vscodium";
    label = "VSCodium";
    group = "Development";
    description = "VS Code without Microsoft's branding and telemetry. An editor for the desktops.";
    system.environment.systemPackages = [ pkgs.vscodium ];
  }
  {
    id = "playwright";
    label = "Playwright browsers";
    group = "Development";
    description = "Browsers built for Playwright on NixOS, where the ones it downloads do not run. Use Playwright ${pkgs.playwright-driver.version} to match.";
    system.environment = {
      systemPackages = [ pkgs.playwright-test ];
      variables = {
        PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
      };
    };
  }

  # Office, graphics and media
  {
    id = "libreoffice";
    label = "LibreOffice";
    group = "Office";
    description = "Word, Excel and PowerPoint files. Converts them without a window too: soffice --headless --convert-to pdf.";
    system.environment.systemPackages = [ pkgs.libreoffice ];
  }
  {
    id = "blender";
    label = "Blender";
    group = "Graphics and media";
    description = "3D modelling and rendering. Best driven by script (blender -b -P script.py); renders on the CPU.";
    system.environment.systemPackages = [ pkgs.blender ];
  }
  {
    id = "gimp";
    label = "GIMP";
    group = "Graphics and media";
    description = "Photo and image editing.";
    system.environment.systemPackages = [ pkgs.gimp ];
  }
  {
    id = "inkscape";
    label = "Inkscape";
    group = "Graphics and media";
    description = "Vector drawing. Its command line turns SVG into PNG or PDF.";
    system.environment.systemPackages = [ pkgs.inkscape ];
  }
  {
    id = "obs";
    label = "OBS Studio";
    group = "Graphics and media";
    description = "Records a desktop, for demos.";
    system.environment.systemPackages = [ pkgs.obs-studio ];
  }
]
