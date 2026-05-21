#!/usr/bin/env bash
# crrow/dotfiles — bash bootstrap.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
#
# Only does what bash uniquely can on a vanilla macOS: install Homebrew
# (which brings Xcode CLT with it) and install bun. Everything else lives
# in TypeScript — fetched and run by bun on the next line.

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only (saw $(uname -s))"

# 1. Homebrew (its installer also handles Xcode Command Line Tools, so we
#    don't need a separate `xcode-select --install` GUI dance).
if ! command -v brew >/dev/null; then
  log "Installing Homebrew (will prompt for your sudo password)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
else fail "brew not on PATH after install"
fi

# 2. bun (the runtime for the real installer).
command -v bun >/dev/null || { log "brew install bun"; brew install bun; }

# 3. Hand off to TypeScript. Fetch into a tmp file so bun gets a real path
#    (cleaner errors / source maps than `bun run <url>`), then exec it.
ref="${DOTFILES_REF:-main}"
tmp="$(mktemp -t dotfiles-install).ts"
trap 'rm -f "$tmp"' EXIT
log "fetching scripts/install.ts@${ref}"
curl -fsSL "https://raw.githubusercontent.com/crrow/dotfiles/${ref}/scripts/install.ts" >"$tmp"
exec bun run "$tmp"
