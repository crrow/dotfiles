#!/usr/bin/env bash
#
# crrow/dotfiles — one-shot bootstrap (Nix-based).
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
#
# What it does (each step skipped if already done — re-run is a no-op):
#   1. Install Determinate Nix
#   2. Clone (or update) the repo at $DOTFILES_DIR
#   3. `darwin-rebuild switch --flake .` against the declared system
#
# Locking: only one install can run at a time. Stale locks (owner dead) are
# auto-released. Signal traps clean up the lock on Ctrl-C.
#
# Env knobs:
#   DOTFILES_DIR  target checkout path (default: ~/code/personal/dotfiles)
#   DOTFILES_REF  branch / tag / commit            (default: main)
#   DOTFILES_REPO override the upstream URL        (default: github.com/crrow/dotfiles)

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------- constants ---

readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"
readonly DOTFILES_REF="${DOTFILES_REF:-main}"
readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/crrow/dotfiles.git}"
readonly LOCK_DIR="${TMPDIR:-/tmp}/crrow-dotfiles-install.lock"
readonly NIX_FLAGS=(--extra-experimental-features nix-command --extra-experimental-features flakes)

# ----------------------------------------------------------------- logging ---

if [[ -t 1 ]]; then
  readonly C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m'
  readonly C_RED=$'\033[1;31m'  C_DIM=$'\033[2m'      C_RESET=$'\033[0m'
else
  readonly C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_RESET=''
fi

log()  { printf '%s==>%s %s\n'   "$C_BLUE"  "$C_RESET" "$*"; }
ok()   { printf '  %s✓%s %s\n'   "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n'   "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '%s!!%s %s\n'    "$C_RED"   "$C_RESET" "$*" >&2; exit 1; }
dim()  { printf '  %s%s%s\n'     "$C_DIM"   "$*"       "$C_RESET"; }

# ------------------------------------------------------------------ locking ---

acquire_lock() {
  # mkdir is atomic — succeeds for exactly one caller. If we lose the race,
  # check whether the holder is still alive; clean up stale locks.
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    trap release_lock EXIT
    trap 'release_lock; exit 130' INT TERM
    return
  fi

  local owner=""
  [[ -f "$LOCK_DIR/pid" ]] && owner=$(<"$LOCK_DIR/pid")

  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
    fail "another install (pid $owner) is in progress; lock at $LOCK_DIR"
  fi

  warn "stale lock at $LOCK_DIR (owner pid=${owner:-unknown} no longer alive) — clearing"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap release_lock EXIT
  trap 'release_lock; exit 130' INT TERM
}

release_lock() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# ----------------------------------------------------------------- prereqs ---

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "macOS only (saw $(uname -s))"
}

source_nix_profile() {
  # Determinate's installer drops a multi-user profile script; source it so
  # `nix` is on PATH for the rest of this script even on the first install.
  local profile=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  # shellcheck source=/dev/null
  [[ -f "$profile" ]] && . "$profile"
}

# --------------------------------------------------------------------- nix ---

install_nix() {
  log "Nix"
  if command -v nix >/dev/null 2>&1; then
    ok "already installed ($(nix --version 2>/dev/null || echo unknown))"
    return
  fi

  log "Installing Determinate Nix (will prompt for sudo)"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install macos --no-confirm

  source_nix_profile
  command -v nix >/dev/null || fail "nix still not on PATH after install"
  ok "installed"
}

# -------------------------------------------------------------------- repo ---

fetch_repo() {
  log "Repo at $DOTFILES_DIR (ref=$DOTFILES_REF)"

  # Already a git checkout? Try to update in place. We can't do this without
  # git, so detect git first; if absent we fall through to a tarball refresh.
  if [[ -d "$DOTFILES_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    update_via_git
    return
  fi

  # No git yet (vanilla macOS), or no existing checkout. Use a tarball — it
  # avoids the Xcode CLT stub AND the cost of materialising a `nix run
  # nixpkgs#git` closure just to clone one tiny repo. git itself lands later
  # when nix-darwin builds Home Manager.
  fresh_tarball
}

fresh_tarball() {
  local owner_repo tar_url
  owner_repo=$(printf '%s' "$DOTFILES_REPO" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')
  tar_url="https://codeload.github.com/${owner_repo}/tar.gz/refs/heads/${DOTFILES_REF}"
  log "downloading $tar_url"

  rm -rf "$DOTFILES_DIR"
  mkdir -p "$DOTFILES_DIR"
  # --strip-components=1 unwraps GitHub's `<repo>-<sha>/...` top dir.
  curl -fsSL "$tar_url" | tar -xz -C "$DOTFILES_DIR" --strip-components=1
  ok "fetched as tarball"
}

update_via_git() {
  if ! git -C "$DOTFILES_DIR" fetch --quiet origin "$DOTFILES_REF"; then
    warn "git fetch failed — keeping local copy as-is"
    return
  fi
  if ! git -C "$DOTFILES_DIR" checkout --quiet "$DOTFILES_REF" 2>/dev/null; then
    warn "could not checkout $DOTFILES_REF (local changes?) — keeping current branch"
    return
  fi
  if ! git -C "$DOTFILES_DIR" pull --ff-only --quiet; then
    warn "git pull --ff-only failed (diverged?) — keeping local commits"
    return
  fi
  ok "up-to-date with origin/$DOTFILES_REF"
}

# ------------------------------------------------------------------ switch ---

darwin_rebuild_switch() {
  log "darwin-rebuild switch --flake ."
  cd "$DOTFILES_DIR"
  # `nix run nix-darwin#darwin-rebuild` bootstraps nix-darwin itself on first
  # use; from then on the same command keeps converging the system.
  nix "${NIX_FLAGS[@]}" run nix-darwin/master#darwin-rebuild -- switch --flake .
  ok "system converged to declared state"
}

# -------------------------------------------------------------------- main ---

main() {
  require_macos
  acquire_lock
  install_nix
  source_nix_profile
  fetch_repo
  darwin_rebuild_switch
  log "done"
  dim "open a new shell to pick up your new \$SHELL/\$PATH"
}

main "$@"
