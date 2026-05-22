{ ... }:

# yabai (tiling) + skhd (hotkeys) + sketchybar (status bar). The binaries
# come from Homebrew (declared in modules/darwin.nix); this module owns
# the user-level configs.
#
# First-time setup the user must do manually (these can't be declared
# from Nix because they need GUI consent):
#   1. System Settings → Privacy & Security → Accessibility:
#        enable yabai, skhd, sketchybar
#   2. brew services start yabai skhd sketchybar
#   3. cd ~/.config/sketchybar/helpers/event_providers/*/  && make
#      (rebuilds the C event-provider binaries this repo doesn't ship)

{
  ###
  ### yabai — config symlinked from ./yabai/yabairc
  ###
  home.file.".config/yabai/yabairc" = {
    source     = ../../yabai/yabairc;
    executable = true;
  };

  ###
  ### skhd — config symlinked from ./skhd/skhdrc
  ###
  home.file.".config/skhd/skhdrc".source = ../../skhd/skhdrc;

  ###
  ### sketchybar — whole tree symlinked from ./sketchybar/
  ### Helpers' compiled binaries are NOT in the repo; rebuild via the
  ### Makefile in each helpers/event_providers/* subdir.
  ###
  home.file.".config/sketchybar" = {
    source    = ../../sketchybar;
    recursive = true;
  };
}
