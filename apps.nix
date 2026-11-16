# Optional software. The setup wizard shows this list, in this order, and
# `apps` in settings.nix records which ids are switched on.
#
# An entry is one of two kinds:
#   system = { ... }   NixOS settings, applied by a system rebuild
#   npm    = "name"    a command-line tool from the npm registry, installed
#                      into the agent account with `bun add -g`, so it can
#                      update itself
#
#   flatpak = "id"  a desktop app from Flathub, by its Flatpak id, for apps
#                      nixpkgs lacks or builds badly. Choosing one turns on
#                      Flatpak; the rebuild installs it (modules/apps.nix).
#
# An npm entry may also have `setup`, a command the agent account runs once
# the package is installed, and `teardown`, run before it is removed. Any
# entry may have `signin`, the command that signs it in to its service,
# shown once it is installed (for tools that sign in from a terminal, not
# from Settings).
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
  {
    id = "gemini-cli";
    label = "Gemini CLI";
    group = "Agents";
    description = "Google's coding agent for the terminal. Signs in on first run: gemini.";
    npm = "@google/gemini-cli";
  }
  {
    id = "copilot-cli";
    label = "GitHub Copilot CLI";
    group = "Agents";
    description = "GitHub's coding agent for the terminal, with a Copilot plan. Signs in with /login inside copilot.";
    npm = "@github/copilot";
  }
  {
    id = "amp";
    label = "Amp";
    group = "Agents";
    description = "Amp's coding agent for the terminal (ampcode.com).";
    # @sourcegraph/amp is now a wrapper whose command Bun does not link.
    npm = "@ampcode/cli";
    signin = "amp login";
  }

  # Services: the command-line tools of the services apps ship to.
  {
    id = "cloudflare";
    label = "Cloudflare CLI";
    group = "Services";
    description = "cf, for Cloudflare: Workers, DNS, R2 and the rest of the account.";
    npm = "cf";
    signin = "cf auth login --no-browser";
  }
  {
    id = "vercel";
    label = "Vercel CLI";
    group = "Services";
    description = "vercel, for deploying web apps to Vercel, with preview links, logs and environment variables.";
    npm = "vercel";
    signin = "vercel login";
  }
  {
    id = "railway";
    label = "Railway CLI";
    group = "Services";
    description = "railway, for deploying services and databases to Railway and reading their logs.";
    npm = "@railway/cli";
    signin = "railway login --browserless";
  }
  {
    id = "supabase";
    label = "Supabase CLI";
    group = "Services";
    description = "supabase, for Supabase projects: migrations, types, edge functions, and a local copy of the stack in Docker.";
    # Supabase does not support a global npm install.
    system.environment.systemPackages = [ pkgs.supabase-cli ];
    signin = "supabase login";
  }
  {
    id = "stripe";
    label = "Stripe CLI";
    group = "Services";
    description = "stripe, for Stripe's API, test events, and webhooks forwarded to a local server: stripe listen --forward-to localhost:3000/webhook.";
    system.environment.systemPackages = [ pkgs.stripe-cli ];
    signin = "stripe login";
  }
  {
    id = "eas";
    label = "Expo EAS CLI";
    group = "Services";
    description = "eas, for building, submitting and updating Expo and React Native apps on Expo's servers.";
    npm = "eas-cli";
    signin = "eas login";
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
    description = "Desktop apps from Flathub that nixpkgs lacks. Every Flatpak gets full access to the machine.";
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
    id = "android-sdk";
    label = "Android SDK";
    group = "Development";
    description = "adb, the emulator and what Gradle needs to build Android apps, with JDK 21. The SDK is read-only: a build that wants another SDK version must ask for one installed here.";
    system =
      let
        android = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [
            "35"
            "36"
          ];
          buildToolsVersions = [
            "35.0.0"
            "36.0.0"
          ];
          includeEmulator = true;
          includeSystemImages = true;
          systemImageTypes = [ "google_apis" ];
          abiVersions = [ "x86_64" ];
        };
        sdk = "${android.androidsdk}/libexec/android-sdk";
      in
      {
        nixpkgs.config.android_sdk.accept_license = true;
        environment.systemPackages = [ android.androidsdk ];
        environment.variables = {
          ANDROID_HOME = sdk;
          ANDROID_SDK_ROOT = sdk;
        };
        programs.java = {
          enable = true;
          package = pkgs.jdk21;
        };
        # The emulator runs on KVM.
        users.users.${settings.user}.extraGroups = [ "kvm" ];
      };
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

  # 3D printing
  {
    id = "bambu-studio";
    label = "Bambu Studio";
    group = "3D printing";
    description = "Bambu Lab's slicer, which also sends prints to Bambu printers and watches them. From Flathub: flatpak run com.bambulab.BambuStudio.";
    # Flathub has Bambu's own build. The nixpkgs one is unfree (it downloads
    # Bambu's closed network plugin), so it is not in the binary cache and
    # takes most of an hour to compile.
    flatpak = "com.bambulab.BambuStudio";
  }
  {
    id = "orca-slicer";
    label = "Orca Slicer";
    group = "3D printing";
    description = "A slicer for Bambu, Prusa, Voron, Creality and most other printers, which also sends prints to them over the network.";
    system.environment.systemPackages = [ pkgs.orca-slicer ];
  }
  {
    id = "prusa-slicer";
    label = "PrusaSlicer";
    group = "3D printing";
    description = "Prusa's slicer, for Prusa printers and many others. Slices without a window too: prusa-slicer --export-gcode part.stl.";
    system.environment.systemPackages = [ pkgs.prusa-slicer ];
  }
  {
    id = "openscad";
    label = "OpenSCAD";
    group = "3D printing";
    description = "Parts written as code, the easiest way for an agent to design one: openscad -o part.stl part.scad.";
    # The development snapshot: the 2021 release is far slower on big models.
    system.environment.systemPackages = [ pkgs.openscad-unstable ];
  }
  {
    id = "freecad";
    label = "FreeCAD";
    group = "3D printing";
    description = "Parametric CAD, with sketches and constraints, for parts that need exact dimensions. Scriptable in Python with freecadcmd.";
    system.environment.systemPackages = [ pkgs.freecad ];
  }
]
