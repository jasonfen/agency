{
  description = "agency: a NixOS computer whose only users are AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Decrypts secrets/agency.sops.json at boot (see modules/secrets.nix).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      settings = import ./settings.nix;
      specialArgs = { inherit self settings; };
    in
    {
      # The machine itself. The configuration is always called "agency";
      # the machine's own name is hostName in settings.nix.
      nixosConfigurations.agency = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
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
        kind = if app ? npm then "npm" else "system";
        npm = app.npm or null;
        setup = app.setup or null;
        teardown = app.teardown or null;
        group = app.group or (if app ? npm then "Agents" else "Other");
        description = app.description or "";
      }) (import ./apps.nix { pkgs = nixpkgs.legacyPackages.${system}; inherit settings; });

      packages.${system} = {
        iso = self.nixosConfigurations.installer.config.system.build.isoImage;
        system = self.nixosConfigurations.agency.config.system.build.toplevel;
        default = self.packages.${system}.iso;
      };
    };
}
