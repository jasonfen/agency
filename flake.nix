{
  description = "agency: a NixOS computer whose only users are AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, disko, ... }:
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
          ./hosts/agency
        ];
      };

      # The USB installer that puts the machine above onto the disk.
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [ ./installer ];
      };

      packages.${system} = {
        iso = self.nixosConfigurations.installer.config.system.build.isoImage;
        system = self.nixosConfigurations.agency.config.system.build.toplevel;
        default = self.packages.${system}.iso;
      };
    };
}
