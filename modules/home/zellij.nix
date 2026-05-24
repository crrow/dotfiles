{ ... }:

# zellij config lives in home/dot_config/zellij/config.kdl so it's also
# usable without Nix. Drop programs.zellij — HM's wrapper just renders
# settings to that same file; direct symlink is simpler.
{
  home.file.".config/zellij/config.kdl".source = ../../home/dot_config/zellij/config.kdl;
}
