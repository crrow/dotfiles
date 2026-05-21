#!/usr/bin/env bash
# crrow/dotfiles — one-shot bootstrap (Nix-based).
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
#
# Does the absolute minimum: installs Determinate Nix (or detects an existing
# Nix), clones this repo, then hands off to `darwin-rebuild switch`. Everything
# from there is declared in `flake.nix` + `modules/*.nix`.
#
# Re-running is safe — every step is idempotent. Nix builds always converge
# the system toward the declared state; nothing is left around between runs.
#
# Env knobs:
#   DOTFILES_DIR  where to clone (default: ~/code/personal/dotfiles)
#   DOTFILES_REF  branch / tag / commit (default: main)

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"
DOTFILES_REF="${DOTFILES_REF:-main}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only (saw $(uname -s))"

# 1. Determinate Nix. Their installer is the cleanest path on macOS — flakes
#    on by default, single-command uninstall, no APFS volume surgery on your
#    side.
if ! command -v nix >/dev/null 2>&1; then
  log "Installing Determinate Nix"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install macos --no-confirm
fi
# Source the daemon profile so `nix` is on PATH inside this script too.
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
command -v nix >/dev/null || fail "nix not on PATH after install"

# 2. Clone (or update) the repo. `nix run nixpkgs#git` avoids needing git
#    pre-installed.
GIT='nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git --'
if [[ -d "$DOTFILES_DIR/.git" ]]; then
  log "Updating $DOTFILES_DIR (best-effort)"
  $GIT -C "$DOTFILES_DIR" fetch --quiet origin "$DOTFILES_REF" || true
  $GIT -C "$DOTFILES_DIR" checkout --quiet "$DOTFILES_REF" || true
  $GIT -C "$DOTFILES_DIR" pull --ff-only --quiet || true
else
  log "Cloning to $DOTFILES_DIR"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  $GIT clone --branch "$DOTFILES_REF" https://github.com/crrow/dotfiles.git "$DOTFILES_DIR"
fi
cd "$DOTFILES_DIR"

# 3. Build & switch. `nix run nix-darwin#darwin-rebuild` bootstraps nix-darwin
#    itself; from then on `darwin-rebuild switch --flake .` is what you run
#    for every subsequent change.
log "darwin-rebuild switch --flake ."
nix --extra-experimental-features 'nix-command flakes' run \
  nix-darwin/master#darwin-rebuild -- switch --flake .

log "Done. Open a new shell."
