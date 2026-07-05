#!/usr/bin/env bash
#
# Worktree guard — Claude Code PreToolUse hook for the Bash tool.
#
# Enforces the parallel-development discipline for this repo:
#
#   1. On the *main* worktree: never create or switch to a feature
#      branch. Feature work always happens in a separate worktree under
#      `.worktrees/<slug>`, so multiple agents can edit in parallel
#      without stomping each other's index.
#
#   2. Inside a worktree (`.worktrees/*`): never run
#      `darwin-rebuild switch`. Switch has global side effects (it
#      mutates /run/current-system and Homebrew); two worktrees racing
#      switch would clobber each other. Worktrees may only `build` /
#      `nix flake check` — actual activation happens on main after
#      merge.
#
# Reads the tool's JSON input on stdin. Exit codes:
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
  printf 'Do this instead: %s\n' "$3" >&2
  exit 2
}

# Are we currently inside a `.worktrees/*` checkout?
in_worktree=0
case "$PWD" in
  */.worktrees/*) in_worktree=1 ;;
esac

if [[ $in_worktree -eq 1 ]]; then
  # Worktree rules: build-only, no global activation.
  case "$COMMAND" in
    *"darwin-rebuild switch"* | *"darwin-rebuild activate"*)
      block "darwin-rebuild switch inside a worktree: $COMMAND" \
        "switch has global side effects; concurrent worktrees would clobber each other." \
        "use 'darwin-rebuild build --flake .' here; merge to main before switching"
      ;;
  esac
else
  # Main worktree rules: no feature branches here.
  case "$COMMAND" in
    *"git checkout -b "* | *"git switch -c "* | *"git checkout -B "*)
      block "branch creation on the main worktree: $COMMAND" \
        "parallel agents share this checkout; a branch switch here breaks the others." \
        "git worktree add .worktrees/<slug> -b <slug>"
      ;;
    *"git checkout "* | *"git switch "*)
      # Allow safe forms: returning to main, restoring files, detaching to a remote ref.
      case "$COMMAND" in
        *"git checkout main"* | *"git switch main"*) exit 0 ;;
        *"git checkout origin/"* | *"git switch -"*) exit 0 ;;
        *"git checkout -- "* | *"git checkout --"*) exit 0 ;;
      esac
      block "branch switch on the main worktree: $COMMAND" \
        "parallel agents share this checkout; a branch switch here breaks the others." \
        "git worktree add .worktrees/<slug> <existing-branch>"
      ;;
  esac
fi

exit 0
