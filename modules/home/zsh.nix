{ ... }:

# zsh setup is split:
#
#   1. ~/.zshrc + ~/.zshenv come from home/dot_zshrc + home/dot_zshenv,
#      symlinked here. The .zshrc itself sources oh-my-zsh + p10k +
#      syntax-highlighting + mise + deja with defensive fallbacks, so
#      the same files work outside Nix too (plain dotfiles via chezmoi).
#   2. The dependencies it sources — oh-my-zsh, powerlevel10k,
#      zsh-syntax-highlighting, deja — come from Homebrew, declared
#      in modules/darwin/homebrew.nix. Nothing here installs them.
#   3. ~/.p10k.zsh is a separate dotfile committed at repo root
#      (p10k.zsh) and symlinked in.
{
  home.file.".zshrc".source  = ../../home/dot_zshrc;
  home.file.".zshenv".source = ../../home/dot_zshenv;
  home.file.".p10k.zsh".source = ../../p10k.zsh;
}
