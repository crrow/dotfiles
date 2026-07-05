#!/usr/bin/env bash
#
# doctor.sh — health check for the crrow/dotfiles development environment.
#
# Run this at the start of a session (or after `git pull`) to verify the
# host has everything needed to develop on / apply this flake. It does
# NOT mutate anything — pure diagnostic.
#
# Sections:
#   * Toolchain — nix, git, host shell, optional dev tools
#   * Repo      — flake evaluates clean
#   * VM        — lume installed and baseline image present (warn-only)
#
# Exit code: 0 if no fatal failures, 1 otherwise. Warnings never fail.

set -uo pipefail   # not -e: we want every check to run, not abort on first miss
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { printf 'cannot cd %s\n' "$SCRIPT_DIR" >&2; exit 1; }

# ----------------------------------------------------------------- logging ---

if [[ -t 1 ]]; then
  readonly RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
  readonly BOLD=$'\033[1m' RESET=$'\033[0m'
else
  readonly RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

FATAL=0

ok()      { printf '  %s[ ok ]%s   %s\n'   "$GREEN"  "$RESET" "$1"; }
warn()    { printf '  %s[warn]%s   %s\n'   "$YELLOW" "$RESET" "$1"; }
fail()    { printf '  %s[fail]%s   %s\n'   "$RED"    "$RESET" "$1"; FATAL=$((FATAL + 1)); }
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }

# --------------------------------------------------------------- toolchain ---

check_toolchain() {
  section "Toolchain"

  if command -v nix >/dev/null 2>&1; then
    ok "nix: $(nix --version 2>/dev/null | head -1)"
  else
    fail "nix not found — run ./install.sh, or: curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
  fi

  if command -v git >/dev/null 2>&1; then
    ok "git: $(git --version 2>/dev/null)"
  else
    fail "git not found — install via brew or let install.sh handle it"
  fi

  if command -v darwin-rebuild >/dev/null 2>&1; then
    ok "darwin-rebuild on PATH"
  else
    # Not fatal — install.sh uses `nix run nix-darwin#darwin-rebuild` until
    # the first switch installs the wrapper.
    warn "darwin-rebuild not on PATH — first ./install.sh will install it"
  fi
}

check_repo() {
  section "Repo"

  if [[ ! -f flake.nix ]]; then
    fail "flake.nix missing — wrong directory?"
    return
  fi
  ok "flake.nix present"

  if command -v nix >/dev/null 2>&1; then
    local log
    log=$(mktemp -t dotfiles-doctor-flake)
    if nix --extra-experimental-features 'nix-command flakes' \
         flake metadata --no-write-lock-file >"$log" 2>&1; then
      ok "flake evaluates"
    else
      fail "flake evaluation failed — see $log"
    fi
  else
    warn "skipping flake check (nix missing)"
  fi
}

check_vm() {
  section "VM (warn-only — only needed for fresh-mac testing)"

  if command -v lume >/dev/null 2>&1; then
    ok "lume: $(lume --version 2>/dev/null | head -1)"
  else
    warn "lume not installed — needed for 'just vm-up'. Install with:"
    warn "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)\""
    return
  fi

  if lume ls 2>/dev/null | awk 'NR>1{print $1}' | grep -qx 'dotfiles-test'; then
    ok "baseline VM 'dotfiles-test' present"
  else
    warn "baseline VM missing — pull with: just baseline (~22 GB one-off)"
  fi
}

# ------------------------------------------------------------------- main ---

main() {
  check_toolchain
  check_repo
  check_vm

  printf '\n'
  if [[ "$FATAL" -eq 0 ]]; then
    printf '%s%s ready to work.%s\n' "$BOLD" "$GREEN" "$RESET"
    exit 0
  fi
  printf '%s%s %d fatal check(s) failed — fix the [fail] lines above.%s\n' \
    "$BOLD" "$RED" "$FATAL" "$RESET"
  exit 1
}

main "$@"
