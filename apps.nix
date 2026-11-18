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
  {
    id = "devin";
    label = "Devin CLI";
    group = "Agents";
    description = "Cognition's coding agent for the terminal. T3 Code runs it too, signed in as the same account.";
    signin = "devin auth login --force-manual-token-flow";
    system =
      let
        home = "/home/${settings.user}";
      in
      {
        # Cognition ships Devin CLI only through its install script, into
        # ~/.local/bin, where it updates itself; like the npm apps, it is
        # installed into the agent account rather than by Nix. Its binary
        # runs through nix-ld. This checks at boot, and after a rebuild,
        # that it is there, and installs it if not. `agency apps remove
        # devin` stops checking; ~/.local/bin/devin stays until deleted.
        #
        # It also adds Devin to T3 Code as an ACP provider (acp_devin) that
        # runs this same binary, so T3 Code uses the account `devin auth
        # login` signed in, rather than downloading a second copy. An
        # acp_devin a person already set up is left as it is.
        # Watch it with: journalctl -u agency-devin
        systemd.services.agency-devin = {
          description = "Install Devin CLI and add it to T3 Code";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "agency-firstboot.service"
            "agency-npm-apps.service"
          ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            bash
            curl
            coreutils
            gnutar
            gzip
            unzip
            gnugrep
            gnused
            findutils
            which
            jq
            util-linux
          ];
          serviceConfig = {
            Type = "exec";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 60;
          };
          script = ''
            as_user() {
              runuser -u ${settings.user} -- env HOME=${home} \
                PATH=${home}/.local/bin:$PATH ${pkgs.runtimeShell} -c "$1"
            }

            if [ ! -x ${home}/.local/bin/devin ]; then
              until curl -fsS --max-time 10 -o /dev/null https://cli.devin.ai/install.sh; do
                sleep 5
              done
              echo "Installing Devin CLI"
              as_user "curl -fsSL https://cli.devin.ai/install.sh | bash"
            fi

            # T3 Code's settings, which it reloads when they change.
            t3=${home}/.t3/userdata/settings.json
            if [ -d ${home}/.t3 ] || ${if builtins.elem "t3code" settings.apps then "true" else "false"}; then
              as_user "mkdir -p ${home}/.t3/userdata && { [ -s $t3 ] || echo '{}' >$t3; }"
              if ! jq -e '.providerInstances.acp_devin' $t3 >/dev/null; then
                echo "Adding Devin to T3 Code"
                as_user "jq '.providerInstances.acp_devin = {
                    driver: \"acpRegistry\",
                    config: { agentId: \"devin\", commandPath: \"${home}/.local/bin/devin\" }
                  }' $t3 >$t3.agency && mv $t3.agency $t3"
              fi
            fi
          '';
        };
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
