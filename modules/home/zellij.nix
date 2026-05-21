{ ... }:

{
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
}
