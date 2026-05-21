{ pkgs, user, ... }:

{
  home.username      = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion  = "24.11";

  ###
  ### User-level CLI tools. GUI apps go to homebrew.casks in darwin.nix.
  ###
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    mise
    ripgrep
    zellij
  ];

  ###
  ### zsh
  ###
  programs.zsh = {
    enable                = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion      = true;

    oh-my-zsh = {
      enable  = true;
      plugins = [ "git" "fzf" ];
      # starship owns the prompt — disable OMZ's.
      theme   = "";
    };

    shellAliases = {
      ll = "ls -lah";
      g  = "git";
      zj = "zellij";
    };

    initContent = ''
      # mise: project-local runtime versions
      command -v mise >/dev/null && eval "$(mise activate zsh)"

      # local overrides (not tracked)
      [[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
    '';
  };

  ###
  ### Prompt
  ###
  programs.starship = {
    enable = true;
    settings = {
      add_newline      = true;
      command_timeout  = 1000;
      format = ''
        $directory$git_branch$git_status$rust$golang$nodejs$python$cmd_duration$line_break$character'';
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol   = "[❯](bold red)";
      };
      directory = {
        style             = "bold cyan";
        truncation_length = 4;
        truncate_to_repo  = true;
      };
      git_branch = {
        symbol = " ";
        style  = "bold purple";
      };
      cmd_duration = {
        min_time = 2000;
        format   = " [$duration](dim yellow)";
      };
    };
  };

  ###
  ### Terminal multiplexer
  ###
  programs.zellij = {
    enable = true;
    settings = {
      theme              = "gruvbox-dark";
      default_shell      = "zsh";
      default_layout     = "compact";
      mouse_mode         = true;
      copy_on_select     = true;
      scroll_buffer_size = 100000;
      pane_frames        = false;
      simplified_ui      = true;
    };
  };

  ###
  ### Git
  ###
  programs.git = {
    enable    = true;
    userName  = "crrow";
    userEmail = "hahadaxigua@gmail.com";
    delta.enable = true;
    extraConfig = {
      init.defaultBranch    = "main";
      pull.ff               = "only";
      push.autoSetupRemote  = true;
    };
  };

  ###
  ### Ghostty config — no Home Manager module yet, write the file directly.
  ### When Ghostty bumps `programs.ghostty.enable` upstream, migrate.
  ###
  home.file.".config/ghostty/config".text = ''
    font-family = "JetBrainsMono Nerd Font"
    font-size   = 14
    theme       = "GruvboxDarkHard"

    window-padding-x       = 12
    window-padding-y       = 12
    window-padding-balance = true
    window-decoration      = true
    macos-titlebar-style   = tabs

    cursor-style       = block
    cursor-style-blink = false

    scrollback-limit       = 100000
    copy-on-select         = clipboard
    mouse-hide-while-typing = true

    shell-integration          = zsh
    shell-integration-features = cursor,sudo,title

    keybind = cmd+t=new_tab
    keybind = cmd+w=close_surface
    keybind = cmd+k=clear_screen
  '';

  ###
  ### mise — user-level runtimes (bun, node).
  ###
  home.file.".config/mise/config.toml".text = ''
    [tools]
    bun  = "latest"
    node = "lts"

    [settings]
    experimental                          = true
    idiomatic_version_file_enable_tools   = ["node"]
  '';

  programs.home-manager.enable = true;
}
