#!/usr/bin/env bash
#
# crrow/dotfiles — one-shot bootstrap (Nix-based).
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
#
# Idempotent: each step skips if already done. Re-run is safe.
#
# What stays here vs Nix:
#   * Lock + proxy.env persistence + Determinate install + tarball fetch
#     + Determinate's nix-daemon plist proxy injection + `darwin-rebuild
#     switch` + interactive Accessibility consent.
#   * Everything else (sudoers env_keep, user-launchd setenv, sketchybar
#     compile, SbarLua, yabai/skhd service start) lives in
#     modules/{darwin,home}/ — declarative, runs on every switch.
#
# Env knobs:
#   DOTFILES_DIR   target checkout path  (default: ~/code/personal/dotfiles)
#   DOTFILES_REF   branch / tag / commit (default: main)
#   DOTFILES_REPO  override upstream URL (default: github.com/crrow/dotfiles)

set -euo pipefail
IFS=$'\n\t'

readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"
readonly DOTFILES_REF="${DOTFILES_REF:-main}"
readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/crrow/dotfiles.git}"
readonly LOCK_DIR="${TMPDIR:-/tmp}/crrow-dotfiles-install.lock"
readonly PROXY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/proxy.env"
readonly NIX_PROFILE=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
readonly NIX_BIN=/nix/var/nix/profiles/default/bin/nix
readonly NIX_FLAGS=(--extra-experimental-features nix-command --extra-experimental-features flakes)

log() { printf '==> %s\n' "$*"; }
fail() {
  printf '!! %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only (saw $(uname -s))"

# mkdir is atomic — only one caller wins. If a stale lock points at a
# dead pid, clear it and retry.
acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local owner=""
    [[ -f "$LOCK_DIR/pid" ]] && owner=$(<"$LOCK_DIR/pid")
    if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
      fail "another install (pid $owner) is in progress"
    fi
    rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR"
  fi
  printf '%s\n' "$$" >"$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
  trap 'rm -rf "$LOCK_DIR"; exit 130' INT TERM
}

# Detect proxy from env (the only place a fresh curl|bash sees it), or
# fall back to the persisted file on re-runs. Persist either way; the
# rest of the stack (zsh.envExtra, HM proxyLaunchd, sudoers drop-in,
# nix-daemon plist) reads from $PROXY_FILE or the exported vars.
persist_proxy() {
  local p="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}}}"
  if [[ -z "$p" && -f "$PROXY_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$PROXY_FILE"
    p="${HTTPS_PROXY:-${https_proxy:-}}"
  fi
  [[ -z "$p" ]] && return 0

  export HTTPS_PROXY="$p" HTTP_PROXY="$p" ALL_PROXY="$p"
  export https_proxy="$p" http_proxy="$p" all_proxy="$p"
  mkdir -p "$(dirname "$PROXY_FILE")"
  cat >"$PROXY_FILE" <<EOF
# Written by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ). Delete to disable.
export HTTPS_PROXY="$p" HTTP_PROXY="$p" ALL_PROXY="$p"
export https_proxy="$p" http_proxy="$p" all_proxy="$p"
EOF
  log "proxy: $p"
}

# Determinate Nix's daemon plist is root-owned, launchd-managed, and
# NOT under nix-darwin's control. So this injection has to live in
# shell, not Nix. No-op when no proxy.
nix_daemon_proxy() {
  [[ -z "${HTTPS_PROXY:-}" ]] && return 0
  local plist=/Library/LaunchDaemons/systems.determinate.nix-daemon.plist
  [[ -f "$plist" ]] || return 0

  log "nix-daemon: inject proxy into launchd plist"
  sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$plist" 2>/dev/null || true
  local k v
  for k in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy; do
    v="${!k:-}"
    [[ -z "$v" ]] && continue
    sudo /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$k" "$plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$k string $v" "$plist"
  done
  # `kickstart -k` doesn't pick up plist env changes — need a full
  # bootout/bootstrap, and the daemon's KeepAlive may respawn it past
  # bootout, so kill stragglers too.
  sudo launchctl bootout system "$plist" 2>/dev/null || true
  sudo pkill -9 -f nix-daemon 2>/dev/null || true
  sleep 1
  sudo launchctl bootstrap system "$plist"
  sleep 3
}

# Determinate's profile script self-guards via __ETC_PROFILE_NIX_SOURCED.
# Clear the guard so a Terminal session-restored shell re-applies PATH.
# Always exit 0 — on first install the file doesn't exist yet.
source_nix() {
  unset __ETC_PROFILE_NIX_SOURCED
  # shellcheck source=/dev/null
  [[ -f "$NIX_PROFILE" ]] && . "$NIX_PROFILE"
  return 0
}

install_nix() {
  source_nix
  command -v nix >/dev/null 2>&1 && return 0
  log "Installing Determinate Nix (will prompt for sudo)"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install macos --no-confirm
  source_nix
  command -v nix >/dev/null || fail "nix not on PATH after install"
}

# Tarball over git: no Xcode CLT dance, no nixpkgs#git closure. The
# user can `git init && git remote add` once HM lands real git.
fetch_repo() {
  [[ -f "$DOTFILES_DIR/flake.nix" ]] && return 0
  log "Fetching $DOTFILES_REPO@$DOTFILES_REF → $DOTFILES_DIR"
  local owner_repo
  owner_repo=$(printf '%s' "$DOTFILES_REPO" |
    sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')
  mkdir -p "$DOTFILES_DIR"
  curl -fsSL "https://codeload.github.com/${owner_repo}/tar.gz/refs/heads/${DOTFILES_REF}" |
    tar -xz -C "$DOTFILES_DIR" --strip-components=1
}

# nix-darwin ≥ 25.x requires darwin-rebuild to run as root. sudo's
# secure_path strips /nix/... so we hand the absolute path; --flake
# gets an absolute path because sudo's cwd is unreliable.
darwin_switch() {
  printf '%s\n' "$USER" >"$DOTFILES_DIR/.user"
  log "darwin-rebuild switch --flake $DOTFILES_DIR"
  sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,http_proxy,https_proxy,ALL_PROXY,all_proxy \
    "$NIX_BIN" "${NIX_FLAGS[@]}" \
    run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES_DIR"
}

# The HM activation already started yabai/skhd launchd agents, but TCC
# is SIP-protected — only the user can grant Accessibility. Once they
# do, restart so the newly-granted permission takes effect.
grant_accessibility() {
  command -v yabai >/dev/null 2>&1 || return 0
  log "Accessibility consent (one-time, manual)"
  printf '   System Settings will open at Privacy & Security → Accessibility.\n'
  printf '   Tick yabai and skhd, then come back here and press ENTER.\n'
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
  [[ -t 0 ]] || {
    printf '   (no tty — manually restart: yabai --restart-service && skhd --restart-service)\n'
    return 0
  }
  read -rp "   Press ENTER when ready (Ctrl-C to skip)... " </dev/tty || return 0
  local svc
  for svc in yabai skhd; do
    command -v "$svc" >/dev/null && "$svc" --restart-service >/dev/null 2>&1 || true
  done
}

main() {
  acquire_lock
  persist_proxy
  install_nix
  nix_daemon_proxy
  fetch_repo
  darwin_switch
  grant_accessibility
  log "done — open a new shell to pick up \$SHELL/\$PATH"
}

main "$@"
