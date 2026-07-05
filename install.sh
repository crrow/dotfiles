#!/usr/bin/env bash
#
# crrow/dotfiles — one-shot bootstrap. Install Nix, fetch the repo,
# hand off to nix-darwin. Everything else is Nix's job.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
#
# Idempotent: re-runs are no-ops past the first.
#
# Env knobs:
#   DOTFILES_DIR   checkout path        (default: ~/code/personal/dotfiles)
#   DOTFILES_REF   branch / tag / commit (default: main)
#   DOTFILES_REPO  upstream URL          (default: github.com/crrow/dotfiles)

set -euo pipefail

readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"
readonly DOTFILES_REF="${DOTFILES_REF:-main}"
readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/crrow/dotfiles.git}"
readonly LOCK_DIR="${TMPDIR:-/tmp}/crrow-dotfiles-install.lock"
readonly PROXY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/proxy.env"
readonly NIX_PROFILE=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
readonly NIX_BIN=/nix/var/nix/profiles/default/bin/nix

log() { printf '==> %s\n' "$*"; }
fail() {
  printf '!! %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only (saw $(uname -s))"

# Single-install lock. mkdir is atomic; stale locks (owner dead) clear.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner=""
  [[ -f "$LOCK_DIR/pid" ]] && owner=$(<"$LOCK_DIR/pid")
  if [[ -z "$owner" ]]; then
    fail "lock $LOCK_DIR exists with no pid (crashed install?) — remove it manually and re-run"
  fi
  kill -0 "$owner" 2>/dev/null && fail "another install (pid $owner) is in progress"
  rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR"
fi
trap 'rm -rf "$LOCK_DIR"' EXIT
trap 'rm -rf "$LOCK_DIR"; exit 130' INT TERM
printf '%s\n' "$$" >"$LOCK_DIR/pid"

# (1) Persist proxy if env has one. This file is the SINGLE source of
# truth for every Nix module that needs proxy (sudoers env_keep, zshenv
# sourcing, nix-daemon plist injection, /etc/{gitconfig,curlrc}). Nothing
# else in install.sh touches proxy — Nix handles propagation.
proxy="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}}}"
if [[ -z "$proxy" && -f "$PROXY_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$PROXY_FILE"
  proxy="${HTTPS_PROXY:-${https_proxy:-}}"
fi
if [[ -n "$proxy" ]]; then
  export HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" ALL_PROXY="$proxy"
  export https_proxy="$proxy" http_proxy="$proxy" all_proxy="$proxy"
  mkdir -p "$(dirname "$PROXY_FILE")"
  # 0600: the proxy URL may carry credentials; never world-readable.
  # Contract: even so, do NOT put user:pass in the proxy URL — it also
  # flows into /etc/curlrc + /etc/gitconfig (0644) via modules/darwin/proxy.nix.
  (
    umask 077
    printf '# Written by install.sh on %s\nexport HTTPS_PROXY=%q HTTP_PROXY=%q ALL_PROXY=%q\nexport https_proxy=%q http_proxy=%q all_proxy=%q\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$proxy" "$proxy" "$proxy" "$proxy" "$proxy" "$proxy" >"$PROXY_FILE"
  )
  chmod 600 "$PROXY_FILE"
  log "proxy: $proxy"
fi

# (2) Install Determinate Nix (idempotent — skip if already present).
unset __ETC_PROFILE_NIX_SOURCED
# shellcheck source=/dev/null
[[ -f "$NIX_PROFILE" ]] && . "$NIX_PROFILE"
if ! command -v nix >/dev/null 2>&1; then
  log "Installing Determinate Nix"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install macos --no-confirm
  # shellcheck source=/dev/null
  . "$NIX_PROFILE"
  command -v nix >/dev/null || fail "nix not on PATH after install"
fi

# (2b) Inject proxy into Determinate's nix-daemon launchd plist. Has
# to live here, not in modules/darwin/nix-daemon-proxy.nix: the first
# darwin-rebuild switch *itself* uses nix-daemon to fetch nixpkgs, so
# the daemon needs the proxy in its env BEFORE switch runs. The Nix
# module duplicates this for re-switches (idempotent).
plist=/Library/LaunchDaemons/systems.determinate.nix-daemon.plist
if [[ -n "${HTTPS_PROXY:-}" && -f "$plist" ]]; then
  log "nix-daemon: inject proxy into launchd plist"
  sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$plist" 2>/dev/null || true
  for k in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy; do
    v="${!k:-}"
    [[ -z "$v" ]] && continue
    sudo /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$k" "$plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$k string $v" "$plist"
  done
  # `kickstart -k` doesn't pick up plist env changes — need full
  # bootout/bootstrap. KeepAlive may respawn past bootout, kill
  # stragglers by name to be sure.
  sudo launchctl bootout system "$plist" 2>/dev/null || true
  sudo pkill -9 -f nix-daemon 2>/dev/null || true
  sleep 1
  sudo launchctl bootstrap system "$plist"
  sleep 3
fi

# (3) Fetch repo (tarball — no git dependency yet). Skip if present.
if [[ ! -f "$DOTFILES_DIR/flake.nix" ]]; then
  log "Fetching $DOTFILES_REPO@$DOTFILES_REF → $DOTFILES_DIR"
  owner_repo=$(printf '%s' "$DOTFILES_REPO" |
    sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')
  mkdir -p "$DOTFILES_DIR"
  curl --proto '=https' --tlsv1.2 -fsSL "https://codeload.github.com/${owner_repo}/tar.gz/refs/heads/${DOTFILES_REF}" |
    tar -xz -C "$DOTFILES_DIR" --strip-components=1
fi

# (4) Hand off to Nix. From here on, everything declarative —
# sudoers, /etc/gitconfig, /etc/curlrc, Xcode CLT, nix-daemon proxy
# plist, HM activation, brew bundle — all live in modules/.
#
# .user pins the primary user so the flake works for any login (gitignored).
# `path:` URI bypasses git-tree mode so the gitignored .user is visible.
# Spaces are URL-encoded for nix's path: parser.
# --preserve-env passes proxy through to nix-daemon's libcurl.
printf '%s\n' "$USER" >"$DOTFILES_DIR/.user"
log "darwin-rebuild switch --flake path:$DOTFILES_DIR"
sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,http_proxy,https_proxy,ALL_PROXY,all_proxy \
  "$NIX_BIN" --extra-experimental-features nix-command --extra-experimental-features flakes \
  run nix-darwin/master#darwin-rebuild -- switch --flake "path:${DOTFILES_DIR// /%20}"

log "done — open a new shell to pick up \$SHELL/\$PATH"
log "one-time: grant Accessibility to yabai+skhd in System Settings, then 'just postinstall'"
