{ ... }:

# lume's vanilla macOS VM — used by `just vm-up` to test the bootstrap
# end-to-end on a clean install. Identical to the real-Mac host today;
# the separate file is a hook for VM-only overrides (e.g. lighter brew
# closures, disable yabai accessibility step) when needed.
{
  imports = [
    ../../modules/darwin
  ];
}
