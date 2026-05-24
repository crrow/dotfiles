{ ... }:

# mise manages per-project runtimes (bun, node, …). Global config
# lives in home/dot_config/mise/config.toml so it's also usable without
# Nix (chezmoi / manual symlink). Project-local `mise.toml` files
# override per-directory.
{
  home.file.".config/mise/config.toml".source = ../../home/dot_config/mise/config.toml;
}
