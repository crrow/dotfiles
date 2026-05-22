{ ... }:

{
  # Home Manager has no programs.ghostty module yet; write config + shader
  # files directly. Source matches ~/Library/Application Support/com.mitchellh.ghostty/config
  # on the host this flake was written for.
  home.file.".config/ghostty/config".text = ''
    cursor-style                   = bar
    cursor-opacity                 = 0.8
    cursor-invert-fg-bg            = true

    font-family                    = "SeriousShanns Nerd Font Mono"
    font-size                      = 14
    font-thicken                   = true

    macos-titlebar-style           = tabs
    window-height                  = 30
    window-width                   = 110

    # Look and feel
    adjust-cursor-thickness        = 3
    adjust-underline-position      = 3
    bold-is-bright                 = true
    link-url                       = true
    mouse-hide-while-typing        = true
    window-vsync                   = true
    background-opacity             = 0.8
    background-blur                = true

    # Shader (bundled in repo; symlinked via home.file below)
    custom-shader-animation        = always
    custom-shader                  = shaders/just-snow.glsl
  '';

  # Ghostty resolves `custom-shader = shaders/X.glsl` relative to the
  # config file location. Symlink the shader next to it.
  home.file.".config/ghostty/shaders/just-snow.glsl".source =
    ../../ghostty/shaders/just-snow.glsl;
}
