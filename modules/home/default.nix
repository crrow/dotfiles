{ pkgs, user, ... }:

{
  imports = [
    ./zsh.nix
    ./zellij.nix
    ./git.nix
    ./ghostty.nix
    ./mise.nix
    ./fonts.nix
    ./neovim.nix
    ./vscode.nix
    ./zed.nix
    ./wallpaper.nix
    ./window-manager.nix
    ./proxy.nix
  ];

  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";

  # User-level CLI tools. GUI apps go through homebrew.casks in darwin.nix
  # because the brew cask path is still the canonical install for most
  # macOS apps (signed, sandboxed, lives in /Applications, auto-updates).
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    mise
    ripgrep
    zellij
  ];

  programs.home-manager.enable = true;
}
