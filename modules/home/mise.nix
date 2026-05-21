{ ... }:

{
  # mise manages per-project runtimes (bun, node, …). This is its global
  # config — project-local `mise.toml` files override per-directory.
  home.file.".config/mise/config.toml".text = ''
    [tools]
    bun  = "latest"
    node = "lts"

    [settings]
    experimental                        = true
    idiomatic_version_file_enable_tools = ["node"]
  '';
}
