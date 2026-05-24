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

    # Declarative Homebrew: nix-homebrew installs and owns the brew
    # binary itself. With it, `homebrew.enable = true` in nix-darwin no
    # longer depends on a system-installed brew — install.sh stops
    # needing the curl|sh Homebrew installer entirely.
    #
    # No nixpkgs.follows: nix-homebrew does not declare a nixpkgs input
    # of its own; following a non-existent input is a warning.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Marketplace + Open VSX extensions as Nix packages, auto-updated.
    # Used by modules/home/vscode.nix for declarative `programs.vscode`
    # extensions — covers the long tail nixpkgs.vscode-extensions doesn't.
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Binary blobs (wallpapers) live in a separate private repo so this
    # one stays small and text-only. `flake = false` means "fetch as a
    # plain source tree, don't try to evaluate it as a flake".
    # Switch to `github:crrow/wallpapers` if you ever flip the repo public.
    wallpapers = {
      url   = "git+ssh://git@github.com/crrow/wallpapers.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nix-homebrew, nix-vscode-extensions, ... }@inputs:
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

      # mkDarwin :: path -> darwinSystem
      # Each host under ./hosts/<name>/default.nix gets wrapped through
      # this; the host file imports modules/darwin and adds whatever
      # host-specific overrides it needs.
      mkDarwin = hostPath: nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user inputs; };
        modules = [
          hostPath

          # Make `pkgs.vscode-marketplace.*` and `pkgs.open-vsx.*`
          # available everywhere the shared nixpkgs is used (incl. HM,
          # because useGlobalPkgs = true).
          { nixpkgs.overlays = [ nix-vscode-extensions.overlays.default ]; }

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs    = true;
              useUserPackages  = true;
              # If $HOME has a file that conflicts with one HM wants to
              # symlink (common on fresh installs: a pre-existing .zshrc /
              # .gitconfig / etc), rename it to <name>.hm-backup instead of
              # aborting activation. Without this, the first switch on a
              # populated $HOME fails noisily.
              backupFileExtension = "hm-backup";
              extraSpecialArgs = { inherit user inputs; };
              users.${user}    = import ./modules/home;
            };
          }
        ];
      };

      # Auto-discover every subdir under ./hosts as a darwinConfigurations
      # entry. Adding a new machine = `mkdir hosts/<hostname> && touch
      # hosts/<hostname>/default.nix` — no flake edit needed.
      hostsDir = ./hosts;
      hosts = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory")
          (builtins.readDir hostsDir)
      );

      pkgs = nixpkgs.legacyPackages.${system};
    in {
      darwinConfigurations = nixpkgs.lib.genAttrs hosts
        (name: mkDarwin (hostsDir + "/${name}"));

      # `nix fmt` formats the flake with nixfmt — the RFC 166 community
      # standard.
      formatter.${system} = pkgs.nixfmt-rfc-style;

      # `nix develop` drops you into a shell with the tools needed to
      # work *on* this repo (format / lint .nix files). These are dev-time
      # only — they don't belong in home.packages because they're not part
      # of the daily Mac environment, just this repo's editing workflow.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.nixfmt-rfc-style  # `nix fmt` formatter (RFC 166)
          pkgs.statix            # lint: Nix anti-patterns
          pkgs.deadnix           # lint: unused bindings / imports
        ];
      };
    };
}
