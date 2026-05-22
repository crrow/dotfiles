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
readonly DOTFILES_USER="${DOTFILES_USER:-$USER}"
readonly NIX_FLAGS=(--extra-experimental-features nix-command --extra-experimental-features flakes)
readonly USER_FILE_REL=".user"   # at repo root; flake.nix reads it

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

install_homebrew() {
  log "Homebrew"
  if command -v brew >/dev/null 2>&1 \
     || [[ -x /opt/homebrew/bin/brew ]] \
     || [[ -x /usr/local/bin/brew ]]; then
    ok "already installed"
    return
  fi
  # Homebrew's installer also installs the Xcode Command Line Tools, so we
  # don't need a separate `xcode-select --install` GUI dance. It does need
  # sudo — interactive on a real Mac, passwordless in the VM-test setup.
  log "Installing Homebrew (needed by nix-darwin's homebrew.casks module)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
  else fail "brew binary missing after install"
  fi
  ok "installed"
}

install_nix() {
  log "Nix"
  # Determinate Nix's /etc/zshenv only puts nix on PATH for SSH sessions
  # (SHLVL=1, SSH_CONNECTION set). A Terminal.app-spawned login shell
  # misses it, so `command -v nix` would falsely report missing here.
  # Source the profile script unconditionally first — it's a no-op when
  # nix isn't installed yet.
  source_nix_profile
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

  # If a checkout is already here, do NOT touch it — the user may have
  # local edits, an in-progress branch, or commits they haven't pushed.
  # Updates are an explicit, manual operation: `cd $DOTFILES_DIR && git pull`.
  if [[ -f "$DOTFILES_DIR/flake.nix" ]]; then
    ok "repo already present — leaving as-is (run 'git pull' to update)"
    return
  fi

  # First install — fetch as a GitHub tarball. Avoids the Xcode CLT stub
  # detour (no git needed) and the cost of materialising a `nix run
  # nixpkgs#git` closure just to clone one tiny repo. git lands later via
  # Home Manager; the user can `git init && git remote add origin …` then.
  local owner_repo tar_url
  owner_repo=$(printf '%s' "$DOTFILES_REPO" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')
  tar_url="https://codeload.github.com/${owner_repo}/tar.gz/refs/heads/${DOTFILES_REF}"

  log "downloading $tar_url"
  rm -rf "$DOTFILES_DIR"
  mkdir -p "$DOTFILES_DIR"
  # --strip-components=1 unwraps GitHub's `<repo>-<sha>/...` top dir.
  curl -fsSL "$tar_url" | tar -xz -C "$DOTFILES_DIR" --strip-components=1
  ok "fetched"
}

# ------------------------------------------------------------------ switch ---

darwin_rebuild_switch() {
  # Tell the flake which user is the primary one — written to ./.user so
  # darwin-rebuild's inner nix invocations see it (env vars wouldn't
  # cross that boundary; see comment in flake.nix).
  printf '%s\n' "$DOTFILES_USER" > "$DOTFILES_DIR/$USER_FILE_REL"
  log "set $USER_FILE_REL → $DOTFILES_USER"

  log "darwin-rebuild switch --flake $DOTFILES_DIR"
  # nix-darwin ≥ 25.x requires `darwin-rebuild switch` itself to run as root
  # (it used to re-exec sudo internally; that path was removed). We invoke
  # nix via its absolute path because sudo's secure_path strips /nix/...
  # from PATH. Pass --flake as an absolute path because sudo's cwd is
  # unreliable.
  sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,http_proxy,https_proxy,ALL_PROXY,all_proxy \
       /nix/var/nix/profiles/default/bin/nix "${NIX_FLAGS[@]}" \
       run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES_DIR"
  ok "system converged to declared state"
}

# -------------------------------------------------------------------- main ---

main() {
  require_macos
  acquire_lock
  install_homebrew
  install_nix
  source_nix_profile
  fetch_repo
  darwin_rebuild_switch
  log "done"
  dim "open a new shell to pick up your new \$SHELL/\$PATH"
}

main "$@"
