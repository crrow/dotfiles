{ config, pkgs, ... }:

{
  programs.neovim = {
    enable     = true;
    viAlias    = true;
    vimAlias   = true;
    vimdiffAlias = true;
  };

  # nvim config is *not* symlinked into /nix/store — lazy.nvim needs to write
  # to lazy-lock.json after every :Lazy sync, and store paths are read-only.
  # mkOutOfStoreSymlink points $HOME/.config/nvim straight at the repo dir,
  # so lazy.nvim's writes land back in the repo (where they belong; the lock
  # is part of the dotfiles).
  #
  # Hardcoded to $HOME/code/personal/dotfiles/nvim — install.sh's
  # DOTFILES_DIR default. Edit if you clone elsewhere.
  home.file.".config/nvim".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/code/personal/dotfiles/nvim";

  # Tools commonly used by LazyVim formatters/linters/LSPs. Add more as
  # the config grows.
  home.packages = with pkgs; [
    lazygit            # invoked by <leader>gg
    ripgrep            # Telescope grep backend
    fd                 # Telescope find backend
    nodejs             # required by many language servers
  ];
}
