{
  description = "crrow's macOS dotfiles — nix-darwin + Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, ... }:
    let
      # Hardcoded — fork and edit one line if you're not crrow.
      user     = "crrow";
      hostname = "default";
      system   = "aarch64-darwin";
    in {
      # Build with:  darwin-rebuild switch --flake .#default
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user; };
        modules = [
          ./modules/darwin.nix

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs   = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit user; };
              users.${user}   = import ./modules/home.nix;
            };
          }
        ];
      };

      # Convenience: `nix fmt` formats the flake with nixpkgs-fmt.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
