{ ... }:

# Entry for the darwin-side modules. One file per concern — keep this
# list short. Host-specific overrides live under hosts/<hostname>/.
{
  imports = [
    ./system.nix
    ./homebrew.nix
    ./proxy.nix
    ./xcode-clt.nix
    ./nix-daemon-proxy.nix
  ];
}
