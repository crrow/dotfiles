{ pkgs, user, ... }:

{
  ###
  ### Nix daemon + flakes
  ###
  # Determinate Nix manages its own daemon — let it. nix-darwin would
  # otherwise fight it during activation.
  nix.enable = false;

  ###
  ### User + base system
  ###
  users.users.${user}.home = "/Users/${user}";
  nixpkgs.config.allowUnfree = true;
  system.primaryUser = user;
  system.stateVersion = 5;

  ###
  ### macOS defaults — opinionated personal preferences.
  ### `defaults write` keys can be discovered with `defaults read NSGlobalDomain`.
  ###
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions      = true;
      ApplePressAndHoldEnabled    = false;
      InitialKeyRepeat            = 15;
      KeyRepeat                   = 2;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
    dock = {
      autohide              = true;
      autohide-delay        = 0.0;
      autohide-time-modifier = 0.4;
      orientation           = "left";
      tilesize              = 48;
      show-recents          = false;
      mru-spaces            = false;
    };
    finder = {
      AppleShowAllFiles  = true;
      ShowPathbar        = true;
      ShowStatusBar      = true;
      FXPreferredViewStyle = "Nlsv";   # list view
    };
    trackpad.Clicking = true;
    screencapture.location = "~/Pictures/screenshots";
  };

  ###
  ### Homebrew bridge — for casks (GUI apps) and the rare tap-only formula.
  ### CLI tools that exist in nixpkgs go through Home Manager instead.
  ### `cleanup = "uninstall"` removes anything not declared here on every
  ### `darwin-rebuild switch` — strict, declarative, no drift.
  ###
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;       # updates land via `nix flake update`
      upgrade    = true;
      cleanup    = "uninstall";
    };
    taps = [
      # Deja: smarter zsh autosuggestions replacement.
      # https://github.com/Giammarco-Ferranti/deja
      "giammarco-ferranti/deja"

      # yabai + skhd (active fork — the upstream is unmaintained).
      "asmvik/formulae"

      # sketchybar (FelixKratz's status bar)
      "felixkratz/formulae"

      # sketchybar-system-stats event provider
      "joncrangle/tap"
    ];
    brews = [
      "deja"
      "yabai"                      # tiling window manager
      "skhd"                       # hotkey daemon
      "sketchybar"                 # status bar
      "sketchybar-system-stats"    # CPU/mem/network event provider for sketchybar
      "lua"                        # sketchybar's Lua-based config runtime
      "luarocks"                   # for lunajson + SbarLua install (post-install)
    ];
    casks = [
      "ghostty"
    ];
  };

  ###
  ### Enable system zsh — Home Manager handles the user-level config.
  ###
  programs.zsh.enable = true;
}
