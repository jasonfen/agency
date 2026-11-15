# The agent account and the tools agents expect to find.
#
# Agents run as a normal user with passwordless sudo, not as root itself:
# they can do anything, but files they create are owned sensibly and agent
# CLIs that refuse to run as root keep working.
{ config, pkgs, settings, ... }:
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
  programs.appimage = {
    enable = true; # AppImages
    binfmt = true;
  };

  # `npm install -g` and `pip install --user` land in the home directory,
  # so agent CLIs install and update themselves without a system rebuild.
  environment.variables.NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  environment.extraInit = ''
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
  '';

  # A default identity, so `git commit` never stops to ask. Signing in to
  # GitHub replaces it with that account (agency-git-identity).
  programs.git = {
    enable = true;
    config.user = {
      name = settings.user;
      email = "${settings.user}@${if config.networking.hostName != "" then config.networking.hostName else "agency"}.local";
    };
  };

  environment.systemPackages = with pkgs; [
    # shell basics
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

    # code
    gh
    gitIdentity
    nodejs_24
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
