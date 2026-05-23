{ ... }:

# Real Mac host (login name comes from ./.user → flake.nix → specialArgs).
# Host-specific overrides go here; shared system+homebrew state lives in
# modules/darwin/.
{
  imports = [
    ../../modules/darwin
  ];
}
