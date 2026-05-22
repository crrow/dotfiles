{ pkgs, ... }:

{
  programs.neovim = {
    enable     = true;
    viAlias    = true;
    vimAlias   = true;
    vimdiffAlias = true;
  };

  # LazyVim starter config — committed under ./nvim/. Symlink every file
  # into $HOME/.config/nvim so `nvim` finds it. Lazy.nvim manages plugins
  # itself at runtime via lazy-lock.json (which we also ship).
  home.file.".config/nvim" = {
    source    = ../../nvim;
    recursive = true;
  };

  # Tools commonly used by LazyVim formatters/linters/LSPs. Add more as
  # the config grows.
  home.packages = with pkgs; [
    lazygit            # invoked by <leader>gg
    ripgrep            # Telescope grep backend
    fd                 # Telescope find backend
    nodejs             # required by many language servers
  ];
}
