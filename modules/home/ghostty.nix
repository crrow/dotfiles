{ ... }:

# Ghostty config + shader. Home Manager has no programs.ghostty module
# yet, so we just symlink the files into place. Both files double as
# plain-dotfile artefacts (chezmoi-source under home/dot_config/ghostty/).
{
  home.file.".config/ghostty/config".source =
    ../../home/dot_config/ghostty/config;

  # Ghostty resolves `custom-shader = shaders/X.glsl` relative to the
  # config file location. Symlink the shader next to it from the repo's
  # original ghostty/ tree (not duplicated under home/).
  home.file.".config/ghostty/shaders/just-snow.glsl".source =
    ../../ghostty/shaders/just-snow.glsl;
}
