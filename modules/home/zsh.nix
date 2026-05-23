{ pkgs, ... }:

{
  programs.zsh = {
    enable                    = true;
    # zsh-autosuggestions disabled — deja replaces it (both wire into the
    # same POSTDISPLAY widget and would fight). See
    # modules/darwin/homebrew.nix for the deja install.
    autosuggestion.enable     = false;
    syntaxHighlighting.enable = true;
    enableCompletion          = true;

    oh-my-zsh = {
      enable  = true;
      plugins = [ "git" "colorize" ];
      # Theme is empty — powerlevel10k below owns the prompt.
      theme   = "";
    };

    # Powerlevel10k as an external plugin (not via OMZ themes — keeps
    # the OMZ theme machinery out of the path).
    plugins = [
      {
        name = "powerlevel10k";
        src  = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    shellAliases = {
      ll = "ls -lah";
      g  = "git";
      zj = "zellij";
    };

    # Sourced by every zsh invocation (interactive, non-interactive,
    # login). Belongs in .zshenv — not .zshrc — so `sudo -u user -i`
    # during nix-darwin's brew bundle activation also picks it up.
    # The file is machine-local, written by install.sh on first proxy
    # detection; absent on machines without a proxy.
    envExtra = ''
      [ -f "$HOME/.config/dotfiles/proxy.env" ] && . "$HOME/.config/dotfiles/proxy.env"
    '';

    initContent = ''
      # Enable Powerlevel10k instant prompt. Keep this near the top of .zshrc.
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      # Project-local runtimes
      command -v mise >/dev/null && eval "$(mise activate zsh)"

      # Deja — smarter zsh autosuggestions (installed via brew, see darwin.nix)
      command -v deja >/dev/null && eval "$(deja init zsh)"

      # Powerlevel10k user config (committed at repo root, symlinked into $HOME)
      [[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

      # Local overrides (untracked)
      [[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
    '';
  };

  # Symlink the p10k config from the repo into $HOME.
  home.file.".p10k.zsh".source = ../../p10k.zsh;
}
