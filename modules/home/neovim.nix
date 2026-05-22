{ pkgs, ... }:

{
  programs.neovim = {
    enable     = true;
    viAlias    = true;
    vimAlias   = true;
    vimdiffAlias = true;
  };

  # nvim config is symlinked file-by-file (recursive = true) so the parent
  # directory is a real, writable dir — lazy.nvim creates and updates its
  # own lazy-lock.json there. The lock is NOT shipped in the repo (see
  # .gitignore); if you want a pinned seed for fresh installs, ship it
  # under a different name and `cp` it in via an activation hook.
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
