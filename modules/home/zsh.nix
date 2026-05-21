{ ... }:

{
  programs.zsh = {
    enable                    = true;
    autosuggestion.enable     = true;
    syntaxHighlighting.enable = true;
    enableCompletion          = true;

    oh-my-zsh = {
      enable  = true;
      plugins = [ "git" "fzf" ];
      # starship owns the prompt; OMZ's themes would fight it.
      theme   = "";
    };

    shellAliases = {
      ll = "ls -lah";
      g  = "git";
      zj = "zellij";
    };

    initContent = ''
      command -v mise >/dev/null && eval "$(mise activate zsh)"
      [[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
    '';
  };
}
