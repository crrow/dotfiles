#!/usr/bin/env bash
#
# Drift guard — Claude Code PreToolUse hook for the Bash tool.
#
# Blocks (exit 2) commands that mutate state outside the declarative
# pipeline. Anything that's a `darwin-rebuild switch` away from being
# correct should never be run by hand: doing so creates drift that
# vanishes on the next switch (best case) or fights it forever (worst
# case).
#
# Reads the tool's JSON input on stdin; we extract the command string
# and pattern-match. Exit codes:
#   0 — allow
#   2 — block (Claude sees the stderr message)

set -uo pipefail
IFS=$'\n\t'

INPUT=$(cat)
# Real JSON parse — the old grep '"command":"[^"]*"' truncated at the
# first escaped quote, letting `… "msg" && brew install x` slip through.
# python3 ships with macOS; jq stays a non-dependency. Parse failure →
# empty command → allow (hooks fail open, they are advisory).
COMMAND=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null)
# Collapse whitespace runs/newlines so multi-space or line-broken forms
# still hit the substring patterns below.
COMMAND=$(printf '%s' "$COMMAND" | tr -s '[:space:]' ' ')

block() {
  printf 'BLOCKED: %s\n' "$1" >&2
  printf 'Reason: %s\n' "$2" >&2
  printf 'Use the declarative path instead: %s\n' "$3" >&2
  exit 2
}

case "$COMMAND" in
  # `brew install / uninstall` outside the flake. The bridge in
  # `modules/darwin/homebrew.nix` is the only authorised brew caller.
  *"brew install"* | *"brew uninstall"* | *"brew tap"* | *"brew untap"*)
    block "manual brew mutation: $COMMAND" \
      "homebrew is managed by nix-darwin (modules/darwin/homebrew.nix)." \
      "edit modules/darwin/homebrew.nix and run 'darwin-rebuild switch --flake .'"
    ;;

  # `defaults write` for macOS system prefs — must go through
  # system.defaults in modules/darwin/system.nix.
  *"defaults write "*)
    block "manual defaults write: $COMMAND" \
      "macOS defaults are declared in modules/darwin/system.nix (system.defaults)." \
      "find the matching nix-darwin attribute and add it there"
    ;;

  # Manual chsh — login shell is declared (programs.zsh.enable +
  # darwin-rebuild handles registration in /etc/shells).
  *"chsh "*)
    block "manual chsh: $COMMAND" \
      "login shell is declared by nix-darwin." \
      "set users.users.<you>.shell in modules/darwin/system.nix if it isn't already"
    ;;

  # nix-env imperative installs — these go into the user profile and
  # are invisible to the flake.
  *"nix-env -i"* | *"nix-env --install"*)
    block "imperative nix-env install: $COMMAND" \
      "nix-env installs are outside the flake and get clobbered on switch." \
      "add the package to home.packages in modules/home/default.nix"
    ;;
esac

exit 0
