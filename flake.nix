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

      # User is read from $DOTFILES_USER (with $USER as fallback) so the
      # same flake works for any login name. Requires `--impure` on the
      # nix CLI — install.sh passes that flag.
      user = let
        fromEnv = builtins.getEnv "DOTFILES_USER";
        fromUser = builtins.getEnv "USER";
      in
        if fromEnv != "" then fromEnv
        else if fromUser != "" then fromUser
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
