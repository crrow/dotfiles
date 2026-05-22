{ pkgs, lib, ... }:

let
  # Fonts bundled in this repo (not packaged in nixpkgs).
  bundled = ../../fonts;

  # Build a list of every regular file under ./fonts and symlink each
  # into ~/Library/Fonts so macOS picks them up at the user level.
  bundledNames = builtins.attrNames (builtins.readDir bundled);
  bundledFontFiles = lib.listToAttrs (map
    (name: {
      name  = "Library/Fonts/${name}";
      value = { source = "${bundled}/${name}"; };
    })
    bundledNames);
in
{
  ###
  ### Fonts packaged in nixpkgs — installed system-wide via the HM profile.
  ###
  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono   # JetBrainsMono Nerd Font (+ Mono variant)
    maple-mono.NF               # Maple Mono Nerd Font
    comic-mono                  # Comic Mono
  ];

  ###
  ### Fonts NOT in nixpkgs — committed under ./fonts/ and symlinked into
  ### ~/Library/Fonts. Limited to Regular / Bold / Italic / BoldItalic
  ### per face to keep the repo lean (~36 MB).
  ###
  ### Currently bundled:
  ###   * SeriousShanns Nerd Font Mono
  ###   * Ioskeley Mono
  ###   * Google Sans Code (variable + variable italic)
  ###
  ### Menlo / Monaco / Courier New are Apple system fonts — already
  ### present on every macOS install.
  ###
  home.file = bundledFontFiles;

  fonts.fontconfig.enable = true;
}
