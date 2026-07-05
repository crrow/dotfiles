{ pkgs, ... }:

# Git config lives in home/dot_gitconfig + home/dot_gitignore_global so
# it's also usable without Nix. delta (the diff pager) is still installed
# via `home.packages` because we don't get the binary otherwise — but the
# git-side wiring (`pager = delta`, `interactive.diffFilter`, etc.) lives
# in the gitconfig file alongside everything else.
{
  home.file.".gitconfig".source = ../../home/dot_gitconfig;
  home.file.".gitignore_global".source = ../../home/dot_gitignore_global;

  home.packages = [ pkgs.delta ];
}
