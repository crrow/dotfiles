{ lib, ... }:

# Ensure Xcode Command Line Tools are installed before brew bundle runs.
# nix-homebrew installs the brew binary but NOT the CLT, and any
# source-built formula (yabai, skhd, lua, ghostty, …) hits
# `Error: No developer tools installed` without it.
#
# Trick: touching the "in-progress" placeholder makes `softwareupdate -l`
# expose the CLT as an available update, which then installs
# non-interactively. Without the placeholder, the only path is
# `xcode-select --install`, which pops a GUI dialog — fine on a real
# Mac with a user present, blocks VM tests where there isn't one.
#
# DAG-after-itself-and-before-homebrew: this activation script depends
# on nothing, but `homebrew` is forced to depend on it so brew bundle
# starts with the CLT already in place.

let
  installXcodeCltScript = ''
    if [ -d /Library/Developer/CommandLineTools ] \
       && /usr/bin/xcode-select -p >/dev/null 2>&1; then
      exit 0
    fi

    echo "[xcode-clt] installing Command Line Tools…" >&2
    placeholder=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    /usr/bin/touch "$placeholder"

    # macOS BSD sed/grep don't grok `\s`; use POSIX [[:space:]]. The
    # `softwareupdate -l` output line looks like ` * Label: Command Line
    # Tools for Xcode-XX.X`; awk extracts the part after `Label: `.
    label=$(/usr/sbin/softwareupdate -l 2>/dev/null \
      | /usr/bin/awk -F'Label:[[:space:]]*' \
          '/^[[:space:]]*\*.*Command Line Tools/ {print $2}' \
      | /usr/bin/sort -V | /usr/bin/tail -1)

    if [ -n "$label" ]; then
      /usr/sbin/softwareupdate -i "$label" --verbose
    else
      echo "[xcode-clt] no Label found via softwareupdate -l;" >&2
      echo "[xcode-clt] falling back to GUI installer (xcode-select --install)" >&2
      /usr/bin/xcode-select --install 2>/dev/null || true
      until /usr/bin/xcode-select -p >/dev/null 2>&1; do sleep 10; done
    fi
    /bin/rm -f "$placeholder"
  '';
in
{
  # nix-darwin's activationScripts submodule has no .deps; we rely on
  # phase ordering (preActivation runs before homebrew). lib.mkBefore
  # places this text at the start of the merged preActivation block.
  # Add a guard so multiple modules contributing to preActivation can
  # all coexist (each prefixes its own concern).
  system.activationScripts.preActivation.text = lib.mkBefore ''
    ${installXcodeCltScript}
  '';
}
