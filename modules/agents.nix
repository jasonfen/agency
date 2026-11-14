# The agent account and the tools agents expect to find.
#
# Agents run as a normal user with passwordless sudo, not as root itself:
# they can do anything, but files they create are owned sensibly and agent
# CLIs that refuse to run as root keep working.
{ pkgs, settings, ... }:
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

  programs.git.enable = true;

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
