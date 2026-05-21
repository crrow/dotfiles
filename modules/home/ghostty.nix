{ ... }:

{
  # Home Manager has no programs.ghostty module yet; write the config file
  # directly. When upstream lands the module, migrate to its options.
  home.file.".config/ghostty/config".text = ''
    font-family = "JetBrainsMono Nerd Font"
    font-size   = 14
    theme       = "GruvboxDarkHard"

    window-padding-x        = 12
    window-padding-y        = 12
    window-padding-balance  = true
    window-decoration       = true
    macos-titlebar-style    = tabs

    cursor-style       = block
    cursor-style-blink = false

    scrollback-limit        = 100000
    copy-on-select          = clipboard
    mouse-hide-while-typing = true

    shell-integration          = zsh
    shell-integration-features = cursor,sudo,title

    keybind = cmd+t=new_tab
    keybind = cmd+w=close_surface
    keybind = cmd+k=clear_screen
  '';
}
