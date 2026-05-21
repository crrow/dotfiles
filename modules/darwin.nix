{ pkgs, user, ... }:

{
  ###
  ### Nix daemon + flakes
  ###
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "@admin" user ];

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
  ### Homebrew bridge — for casks (GUI apps) only. CLI tools live in Nix.
  ### `cleanup = "uninstall"` removes anything not declared here on every
  ### `darwin-rebuild switch` — strict, declarative, no drift.
  ###
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;       # `nix flake update` is the update path
      upgrade    = true;
      cleanup    = "uninstall";
    };
    casks = [
      "ghostty"
    ];
  };

  ###
  ### Enable system zsh — Home Manager handles the user-level config.
  ###
  programs.zsh.enable = true;
}
