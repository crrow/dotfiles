{ inputs, user, ... }:

# Homebrew, declaratively. Two layers:
#
#   * nix-homebrew owns the brew binary itself (installs into
#     /opt/homebrew on Apple Silicon). install.sh no longer runs the
#     curl|sh Homebrew installer.
#   * nix-darwin's `homebrew.*` declares the taps/brews/casks that get
#     installed via `brew bundle` on every switch.
#
# `cleanup = "uninstall"` removes anything not declared here on every
# `darwin-rebuild switch` — strict, declarative, no drift.

{
  imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

  nix-homebrew = {
    enable = true;
    user   = user;
    # If brew is already installed under /opt/homebrew (e.g. from a
    # pre-existing Mac), adopt that installation instead of failing.
    # Safer than `mutableTaps = false` — we still want manual `brew
    # install` to be possible during incident response.
    autoMigrate = true;
  };

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
      # Shell stack — sourced by home/dot_zshrc. Nothing else wires them.
      "powerlevel10k"              # prompt theme
      "zsh-syntax-highlighting"    # syntax highlighting for zsh
      "deja"                       # smarter autosuggestions (replaces zsh-autosuggestions)

      # Window manager + status bar
      "yabai"                      # tiling window manager
      "skhd"                       # hotkey daemon
      "sketchybar"                 # status bar
      "sketchybar-system-stats"    # CPU/mem/network event provider for sketchybar
      "lua"                        # sketchybar's Lua-based config runtime
      "luarocks"                   # for lunajson + SbarLua install (post-install)
    ];
    casks = [
      "ghostty"
      "zed"
    ];
  };
}
