{
  description = "agency: a NixOS computer whose only users are AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Used instead of nixpkgs when settings.nix has `channel = "unstable";`
    # (see `agency channel`). The installer always uses the stable one.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Decrypts secrets/agency.sops.json at boot (see modules/secrets.nix).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rex, Superlogical's terminal multiplexer, for the `rex` app. Its own
    # flake of the prebuilt binary; the preview channel, since stable has no
    # release yet. `nix flake update rex` moves to the newest preview.
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      disko,
      sops-nix,
      rex,
      ...
    }:
    let
      system = "x86_64-linux";
      settings = import ./settings.nix;
      specialArgs = { inherit self settings; };

      # The package set this machine follows: stable unless settings.nix
      # says `channel = "unstable";`. disko and sops-nix keep following the
      # stable one either way; they are libraries, not the system.
      channel = settings.channel or "stable";
      machinePkgs =
        if channel == "unstable" then
          nixpkgs-unstable
        else if channel == "stable" then
          nixpkgs
        else
          throw "settings.nix: channel must be \"stable\" or \"unstable\", not \"${channel}\"";
    in
    {
      # The machine itself. The configuration is always called "agency";
      # the machine's own name is hostName in settings.nix.
      nixosConfigurations.agency = machinePkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          # pkgs.superlogical-rex, for apps.nix. Not pkgs.rex: nixpkgs
          # already has a Rex, an unrelated Perl deployment tool.
          { nixpkgs.overlays = [ (final: prev: { superlogical-rex = rex.packages.${system}.rex; }) ]; }
          ./hosts/agency
        ];
      };

      # The USB installer that puts the machine above onto the disk.
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [ ./installer ];
      };

      # The app catalog as plain data, for `agency apps`.
      appCatalog = map (app: {
        inherit (app) id label;
        kind =
          if app ? npm then
            "npm"
          else if app ? flatpak then
            "flatpak"
          else if app ? installScript then
            "script"
          else
            "system";
        npm = app.npm or null;
        flatpak = app.flatpak or null;
        setup = app.setup or null;
        teardown = app.teardown or null;
        signin = app.signin or (app.account.signin or null);
        hasAccount = app ? account;
        group = app.group or (if app ? npm then "Agents" else "Other");
        description = app.description or "";
      }) (import ./apps.nix { pkgs = machinePkgs.legacyPackages.${system}; inherit settings; });

      packages.${system} = {
        iso = self.nixosConfigurations.installer.config.system.build.isoImage;
        system = self.nixosConfigurations.agency.config.system.build.toplevel;
        # The machine as a VM, to try it (hosts/agency/vm.nix).
        vm = self.nixosConfigurations.agency.config.system.build.vm;
        default = self.packages.${system}.iso;
      };

      # nix run github:makors/agency#vm
      apps.${system}.vm = {
        type = "app";
        program = "${self.packages.${system}.vm}/bin/run-agency-vm";
        meta.description = "Try agency in a virtual machine";
      };
    };
}
