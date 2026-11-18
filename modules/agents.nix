# The agent account and the tools agents expect to find.
#
# Agents run as a normal user with passwordless sudo, not as root itself:
# they can do anything, but files they create are owned sensibly and agent
# CLIs that refuse to run as root keep working.
{ config, options, pkgs, settings, ... }:
let
  # `agency-git-identity`: once GitHub is signed in, commit as that account,
  # with its private noreply address. A name or email already set in
  # ~/.gitconfig is left alone.
  gitIdentity = pkgs.writeShellScriptBin "agency-git-identity" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.gh pkgs.git pkgs.jq ]}:$PATH
    gh auth status --hostname github.com >/dev/null 2>&1 || exit 0
    me=$(gh api user) || exit 0
    login=$(jq -r .login <<<"$me")
    name=$(jq -r '.name // empty' <<<"$me")
    id=$(jq -r .id <<<"$me")
    git config --global user.name >/dev/null || git config --global user.name "''${name:-$login}"
    git config --global user.email >/dev/null || git config --global user.email "$id+$login@users.noreply.github.com"
  '';
in
{
  users.users.${settings.user} = {
    isNormalUser = true;
    description = "AI agents";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "dialout"
    ];
    # Keep the user's background services running with nobody logged in.
    linger = true;
    openssh.authorizedKeys.keys = settings.sshKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  # Agents download prebuilt programs constantly. These two settings make
  # the usual kinds run on NixOS without per-program fixes:
  programs.nix-ld.enable = true; # generic Linux binaries
  # Its usual libraries, and what a downloaded headless Chrome needs (T3
  # Code's browser, Puppeteer and the like), which nix-ld lacks by default.
  programs.nix-ld.libraries = options.programs.nix-ld.libraries.default ++ (with pkgs; [
    glib nspr nss at-spi2-core dbus expat libxkbcommon libgbm alsa-lib cups
    libx11 libxcomposite libxdamage libxext libxfixes libxrandr libxcb
    pango cairo libdrm
  ]);
  programs.appimage = {
    enable = true; # AppImages
    binfmt = true;
  };

  # `bun add -g`, `npm install -g` and `pip install --user` land in the
  # home directory, so agent CLIs install and update themselves without a
  # system rebuild. Bun is the usual one; npm is there for tools that
  # insist on it.
  environment.variables.BUN_INSTALL = "$HOME/.bun";
  environment.variables.NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  environment.extraInit = ''
    export PATH="$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
  '';

  # A default identity, so `git commit` never stops to ask. Signing in to
  # GitHub replaces it with that account (agency-git-identity).
  programs.git = {
    enable = true;
    lfs.enable = true;
    config.user = {
      name = settings.user;
      email = "${settings.user}@${if config.networking.hostName != "" then config.networking.hostName else "agency"}.local";
    };
  };

  environment.systemPackages = with pkgs; [
    # shell basics
    # Plain coreutils over NixOS's default coreutils-full, which links
    # OpenSSL into every `ls`, `cat` and `true`: 0.42 ms per start instead
    # of 0.73 ms, and agents start a lot of them. Only sha256sum and friends
    # get slower on large files.
    coreutils
    tmux
    curl
    wget
    jq
    ripgrep
    fd
    tree
    unzip
    zip
    file
    htop
    vim
    lsof
    strace
    rsync
    p7zip

    # media, documents and data
    ffmpeg
    pandoc
    poppler-utils # pdftotext, pdftoppm, pdfinfo
    qpdf
    sqlite
    duckdb
    yq-go

    # code
    gh
    gitIdentity
    ast-grep
    nodejs_24
    bun
    python3
    uv
    gcc
    gnumake
    pkg-config

    # system
    btrfs-progs
    pciutils
    usbutils
  ];

  # When memory runs out, stop the process group that is using the most
  # instead of freezing the whole machine.
  systemd.oomd = {
    enable = true;
    enableUserSlices = true;
  };
}
