{ ... }:

# Zed config — the app comes from the `zed` Homebrew cask (modules/
# darwin/homebrew.nix), so Nix has no business installing the binary.
# Config files (settings + keymap) live as plain JSON under
# home/dot_config/zed/ so they're usable without Nix too.
{
  home.file.".config/zed/settings.json".source = ../../home/dot_config/zed/settings.json;
  home.file.".config/zed/keymap.json".source = ../../home/dot_config/zed/keymap.json;
}
