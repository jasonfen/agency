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
#   installScript = "url"
#                      a command-line tool its maker ships only as an install
#                      script that puts `command` in ~/.local/bin, where it
#                      updates itself. agency-script-apps (modules/apps.nix)
#                      runs the script as the agent when the command is
#                      missing. With `t3Agent`, it also adds the tool to T3
#                      Code as that ACP agent, running the same binary. With
#                      `t3Driver`, it adds it as that native T3 Code provider
#                      instead, for a driver whose binary serves ACP itself
#                      (agy), pointing the provider at the binary.
#
# An npm entry may also have `setup`, a command the agent account runs once
# the package is installed, `teardown`, run before it is removed, and
# `replaces`, an older npm package name to uninstall first when migrating.
#
# An agent with its own sign-in has `account`, which puts it under Accounts
# in the dashboard's Settings, with a Sign in button that runs `signin` in
# the dashboard's terminal:
#   account = {
#     program = "claude";                     # installed if on PATH
#     signin = "claude";                      # signs it in, in a terminal
#     signedIn = ".claude/.credentials.json"; # exists once signed in (in ~)
#     # or, when no file says so:
#     check = "...";                          # exits 0 when signed in
#   };
# Any other entry may have `signin`, the command that signs it in to its
# service, which the catalog shows once it is installed.
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
    account = {
      program = "claude";
      signin = "claude";
      signedIn = ".claude/.credentials.json";
    };
  }
  {
    id = "codex";
    label = "Codex CLI";
    group = "Agents";
    description = "OpenAI's coding agent for the terminal.";
    npm = "@openai/codex";
    account = {
      program = "codex";
      signin = "codex login";
      signedIn = ".codex/auth.json";
    };
  }
  {
    id = "opencode";
    label = "OpenCode";
    group = "Agents";
    description = "An open-source coding agent that works with many model providers.";
    npm = "@opencode/cli";
    replaces = "opencode-ai";
    account = {
      program = "opencode";
      signin = "opencode auth login";
      # OpenCode 2 stores credentials in opencode.db rather than auth.json.
      # `auth list --standalone` avoids starting the background service and
      # prints "No authenticated integrations" when signed out.
      check = ''out=$(opencode auth list --standalone 2>/dev/null) && [ -n "$out" ] && case "$out" in *"No authenticated"*) false ;; esac'';
    };
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
    id = "antigravity";
    label = "Antigravity CLI";
    group = "Agents";
    description = "Google's coding agent for the terminal, agy, which replaced Gemini CLI.";
    installScript = "https://antigravity.google/cli/install.sh";
    command = "agy";
    # T3 Code's Antigravity provider, running the CLI installed here. The
    # CLI serves ACP itself, but T3 looks for Google's separate ACP server
    # unless told the path, and reports the provider as not installed.
    t3Driver = "antigravity";
    account = {
      program = "agy";
      # agy signs in on its first run; it has no login command.
      signin = "agy";
      # It keeps its sign-in in no file of its own; asking for the models
      # fails at once, without the network, when it is signed out.
      check = "agy models";
    };
  }
  {
    id = "copilot-cli";
    label = "GitHub Copilot CLI";
    group = "Agents";
    description = "GitHub's coding agent for the terminal, with a Copilot plan. Signs in with /login inside copilot.";
    npm = "@github/copilot";
  }
  {
    id = "devin";
    label = "Devin CLI";
    group = "Agents";
    description = "Cognition's coding agent for the terminal. T3 Code runs it too, signed in as the same account.";
    installScript = "https://cli.devin.ai/install.sh";
    command = "devin";
    t3Agent = "devin";
    account = {
      program = "devin";
      # Pastes a token, as a localhost redirect cannot reach a browser
      # on another machine.
      signin = "devin auth login --force-manual-token-flow";
      signedIn = ".local/share/devin/credentials.toml";
    };
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
    id = "rex";
    label = "Rex server";
    group = "Development";
    description = "Superlogical's terminal multiplexer for agents, whose sessions outlive the window. To connect from Rex for Mac, choose Add Remote Host and enter ssh://${settings.user}@<this machine>.";
    system = {
      environment.systemPackages = [ pkgs.superlogical-rex ];

      # The personal server of the agent account, kept running (the account
      # lingers), so sessions survive the last client leaving. The unit is
      # the one Rex's home-manager module writes. With no --listen it takes
      # the socket in $XDG_RUNTIME_DIR that every `rex` command looks for,
      # so SSH clients reach it and need no open port.
      systemd.user.services.rex = {
        description = "Rex server";
        documentation = [ "https://www.superlogical.com/rex/docs" ];
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = settings.user;
        # A restart ends every session, so a rebuild leaves it running the
        # old version: systemctl --user restart rex when ready.
        restartIfChanged = false;
        environment = {
          # Programs in a Rex terminal (TERM=xterm-rex) look it up here; the
          # empty element keeps the usual entries.
          TERMINFO_DIRS = "${pkgs.superlogical-rex}/share/terminfo:";
          REX_CGROUP_DELEGATED = "1";
        };
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "main";
          ExecStart = "${pkgs.superlogical-rex}/bin/rex server run";
          Restart = "on-failure";
          RestartSec = "5s";
          # SIGTERM to the server alone, which saves its sessions first.
          KillMode = "mixed";
          # One terminal running out of memory doesn't take the rest down.
          OOMPolicy = "continue";
          OOMScoreAdjust = 0;
          Delegate = true;
          DelegateSubgroup = "server";
        };
      };

      # ssh from a Rex terminal announces xterm-256color to hosts that lack
      # Rex's terminfo entry.
      programs.ssh.extraConfig = ''
        Include ${pkgs.superlogical-rex}/share/rex/ssh_config.d/50-rex.conf
      '';
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
    id = "silverbullet";
    label = "SilverBullet";
    group = "Office";
    description = "A Markdown notes and wiki server with Lua scripting. silverbullet <folder> serves the folder on localhost:3000.";
    system.environment.systemPackages = [ pkgs.silverbullet ];
  }
  {
    id = "blender";
    label = "Blender";
    group = "Graphics and media";
    description = "3D modelling and rendering, always the newest stable release from blender.org. Best driven by script (blender -b -P script.py); renders on the CPU.";
    system = {
      # The official build, always the newest stable release; see the file.
      environment.systemPackages = [ (pkgs.callPackage ./pkgs/blender.nix { }) ];
    };
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
