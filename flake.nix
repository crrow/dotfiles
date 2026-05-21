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
      user   = "crrow";
      system = "aarch64-darwin";

      mkDarwin = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user; };
        modules = [
          ./modules/darwin.nix

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs    = true;
              useUserPackages  = true;
              extraSpecialArgs = { inherit user; };
              users.${user}    = import ./modules/home;
            };
          }
        ];
      };

      # darwin-rebuild auto-resolves to darwinConfigurations.$hostname.
      # Expose the same config under every hostname we want this dotfiles
      # repo to drive — add yours here when you set one up.
      hostnames = [
        "default"                 # explicit `--flake .#default`
        "lumes-Virtual-Machine"   # lume's vanilla macOS VM (testing)
      ];
    in {
      darwinConfigurations = nixpkgs.lib.genAttrs hostnames (_: mkDarwin);

      # `nix fmt` formats the flake with nixpkgs-fmt.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
