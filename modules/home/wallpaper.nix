{ inputs, ... }:

# Wallpapers are the `wallpaper/` subdir of the `assets` flake input
# (declared in flake.nix). HM symlinks that subdir into
# ~/Pictures/wallpaper, read-only, pointing at /nix/store.
#
# Workflow when you add/remove wallpapers:
#   1. Drop files into ~/code/personal/assets/wallpaper.
#   2. Commit + push that repo.
#   3. In this repo:   nix flake update assets
#   4.                 darwin-rebuild switch --flake .
#
# Why this shape, not a `home.activation` cp -R:
#   - Source-of-truth stays in git, not a local working copy.
#   - Switching machines pulls the same content automatically.
#   - No mutation of $HOME outside HM's tracking.

{
  home.file."Pictures/wallpaper" = {
    source    = inputs.assets + "/wallpaper";
    recursive = true;
  };
}
