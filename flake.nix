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
      system = "aarch64-darwin";

      # User comes from ./.user (one line, the login name) if it exists,
      # else "crrow". install.sh writes .user on first bootstrap so the
      # same flake works for any login (lume in the VM, crrow on my Mac,
      # any name on a fork). The file is gitignored — it's per-machine.
      #
      # We read a file instead of `builtins.getEnv` because --impure only
      # applies to the outermost nix invocation; darwin-rebuild re-invokes
      # nix internally and that subprocess wouldn't see the var.
      user = if builtins.pathExists ./.user
             then builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./.user)
             else "crrow";

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
      # Expose the same config under every hostname we want this flake to
      # drive; add yours here when you set up a new machine.
      hostnames = [
        "default"                # explicit `--flake .#default`
        "lumes-Virtual-Machine"  # lume's vanilla macOS VM (testing)
      ];
    in {
      darwinConfigurations = nixpkgs.lib.genAttrs hostnames (_: mkDarwin);

      # `nix fmt` formats the flake with nixpkgs-fmt.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
