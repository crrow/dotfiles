{ user, ... }:

# Nix daemon ownership, primary user, and macOS user-visible defaults.
# All `defaults write` keys can be discovered with
# `defaults read NSGlobalDomain` or by greping the nix-darwin source.
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
  ###
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      orientation = "left";
      tilesize = 48;
      show-recents = false;
      mru-spaces = false;
    };
    finder = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "Nlsv"; # list view
    };
    trackpad.Clicking = true;
    screencapture.location = "~/Pictures/screenshots";
  };

  ###
  ### Enable system zsh — Home Manager handles the user-level config.
  ###
  programs.zsh.enable = true;
}
