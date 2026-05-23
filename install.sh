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
  #
  # The script self-guards via __ETC_PROFILE_NIX_SOURCED to avoid re-running
  # in nested shells. macOS Terminal session-restore can preserve that flag
  # across new tabs even when PATH has been reset by /etc/zprofile's
  # path_helper — so the guard short-circuits the PATH export and nix
  # appears "not installed". Clear the guard first; the script is cheap
  # to re-run.
  unset __ETC_PROFILE_NIX_SOURCED
  local profile=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  # shellcheck source=/dev/null
  if [[ -f "$profile" ]]; then
    . "$profile"
  fi
  # Always return 0 — on a fresh machine Nix isn't installed yet and the
  # missing-file check ([[ -f ]] && . …) would propagate 1 through set -e
  # and kill install.sh right after the "==> Nix" log line.
  return 0
}

# --------------------------------------------------------------------- nix ---

install_homebrew() {
  log "Homebrew"
  if command -v brew >/dev/null 2>&1 \
     || [[ -x /opt/homebrew/bin/brew ]] \
     || [[ -x /usr/local/bin/brew ]]; then
    ok "already installed"
    source_brew_shellenv  # idempotent — guarantees brew on PATH for later steps
    return
  fi
  # Homebrew's installer also installs the Xcode Command Line Tools, so we
  # don't need a separate `xcode-select --install` GUI dance. It does need
  # sudo — interactive on a real Mac, passwordless in the VM-test setup.
  #
  # NONINTERACTIVE=1 skips the installer's confirmation prompts (the
  # "Press RETURN to continue or any other key to abort" and the implicit
  # CLT-install opt-in). sudo still prompts on a fresh Mac — that's the
  # one consent we can't avoid.
  log "Installing Homebrew (needed by nix-darwin's homebrew.casks module)"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  source_brew_shellenv
  command -v brew >/dev/null || fail "brew binary missing after install"
  ok "installed"
}

source_brew_shellenv() {
  # `brew shellenv` adds /opt/homebrew/bin (Apple Silicon) or
  # /usr/local/bin (Intel) to PATH, plus MANPATH / INFOPATH. Idempotent —
  # re-sourcing is a no-op. Needed so later steps (post_install_window_manager,
  # any 'command -v yabai' checks) actually see brew-installed binaries even
  # on a re-run where install_homebrew took the early-return path.
  if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
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
    propagate_proxy_to_nix_daemon
    return
  fi

  log "Installing Determinate Nix (will prompt for sudo)"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install macos --no-confirm

  source_nix_profile
  command -v nix >/dev/null || fail "nix still not on PATH after install"
  propagate_proxy_to_nix_daemon
  ok "installed"
}

# If the user shell has HTTPS_PROXY set (corporate proxy, VM-test, …), the
# Determinate Nix daemon — running as root under launchd — doesn't inherit
# it. nix-daemon's libcurl then can't reach github.com, so flake fetches
# stall. Inject the proxy vars into the daemon's launchd plist and reload.
# No-op when no proxy is configured (the common case on a real Mac).
propagate_proxy_to_nix_daemon() {
  [[ -z "${HTTPS_PROXY:-${https_proxy:-}}" ]] && return

  local plist=/Library/LaunchDaemons/systems.determinate.nix-daemon.plist
  [[ -f "$plist" ]] || return

  log "propagating HTTPS_PROXY into nix-daemon launchd plist"
  sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$plist" 2>/dev/null || true
  local k v
  for k in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
    v="${!k:-}"
    [[ -z "$v" ]] && continue
    sudo /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$k" "$plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$k string $v" "$plist"
  done
  # `launchctl kickstart -k` doesn't pick up plist env changes; need full
  # unload/load. The bootout often leaves the daemon respawned (KeepAlive),
  # so we also kill any stragglers by pid.
  sudo launchctl bootout system "$plist" 2>/dev/null || true
  sleep 1
  sudo pkill -9 -f "nix-daemon" 2>/dev/null || true
  sleep 1
  sudo launchctl bootstrap system "$plist"
  sleep 3
  ok "nix-daemon proxy configured"
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

# --------------------------------------------------------- window manager ---

# Three things darwin-rebuild can't do on its own for yabai / skhd:
# (a) compile sketchybar's per-arch C event-provider binaries for the
# optional bar config; (b) register the launchd agents for yabai / skhd;
# (c) grant Accessibility — TCC is SIP-protected, only the user can tick
# the boxes. We do (a) and (b), then open System Settings for (c).
post_install_window_manager() {
  log "window-manager post-install"

  if ! command -v yabai >/dev/null 2>&1 \
     && ! command -v skhd >/dev/null 2>&1 \
     && ! command -v sketchybar >/dev/null 2>&1; then
    warn "none of yabai/skhd/sketchybar on PATH; skipping"
    return
  fi

  # (a) Compile sketchybar's bundled C helpers. Idempotent — `make` no-ops
  # if outputs are up to date.
  local helpers="$HOME/.config/sketchybar/helpers/event_providers"
  if [[ -d "$helpers" ]]; then
    local d
    for d in "$helpers"/*/; do
      [[ -f "$d/makefile" || -f "$d/Makefile" ]] || continue
      log "make $(basename "$d")"
      if (cd "$d" && make >/dev/null 2>&1); then
        ok "built"
      else
        warn "make failed in $d (non-fatal — you'll need to build manually)"
      fi
    done
  fi

  # (a2) SbarLua: the sketchybar Lua bindings (sketchybar.so) the user's
  # config requires via helpers/init.lua. Not on luarocks/nixpkgs; build
  # from upstream. Idempotent — skip if already built.
  if [[ -f "$HOME/.config/sketchybar/sketchybarrc" ]] \
     && [[ ! -f "$HOME/.local/share/sketchybar_lua/sketchybar.so" ]] \
     && command -v lua >/dev/null 2>&1 \
     && command -v luarocks >/dev/null 2>&1; then
    log "build SbarLua (sketchybar.so for the Lua config)"
    local tmpdir
    tmpdir=$(mktemp -d -t sbarlua)
    trap 'rm -rf "$tmpdir"' RETURN
    if (cd "$tmpdir" \
        && git clone --depth 1 https://github.com/FelixKratz/SbarLua.git \
        && cd SbarLua && make install) >/dev/null 2>&1; then
      ok "SbarLua installed to ~/.local/share/sketchybar_lua/"
    else
      warn "SbarLua build failed (sketchybar will render empty bar)"
    fi
    # Companion: lunajson is a pure-Lua dep referenced by some bar items.
    if ! luarocks --lua-version 5.5 list 2>/dev/null | grep -q lunajson; then
      log "luarocks install lunajson"
      if luarocks --lua-version 5.5 install lunajson >/dev/null 2>&1; then
        ok "lunajson installed"
      else
        warn "lunajson install failed"
      fi
    fi
  fi

  # (b) Start launchd agents. The asmvik yabai/skhd fork's brew formula
  # doesn't define a service plist, so we use each tool's built-in
  # --start-service subcommand (writes ~/Library/LaunchAgents/*.plist
  # and loads it). sketchybar is installed/configured but intentionally
  # not started on bootstrap, so a fresh VM keeps the native macOS menu bar.
  local svc started=()
  for svc in yabai skhd; do
    command -v "$svc" >/dev/null 2>&1 || continue
    if "$svc" --start-service >/dev/null 2>&1; then
      started+=("$svc")
    else
      warn "$svc --start-service failed"
    fi
  done
  if (( ${#started[@]} )); then
    ok "launchd agents started: ${started[*]}"
  fi
  if command -v sketchybar >/dev/null 2>&1; then
    dim "sketchybar installed/configured but not started; native menu bar stays active"
  fi

  # (c) Accessibility consent — required for any input-grabbing tool.
  # SIP-protected TCC.db; only the user can tick the boxes. We open the
  # right pane, wait for them to do it, then restart the services so the
  # newly-granted permission takes effect. The same pattern Homebrew uses
  # for its own interactive prompts.
  command -v yabai >/dev/null 2>&1 || return
  log "Accessibility consent (one-time, manual)"
  dim "  System Settings will open at Privacy & Security → Accessibility."
  dim "  Tick yabai and skhd; then come back here and press ENTER."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true

  if [[ -t 0 ]]; then
    # /dev/tty bypasses the curl|bash piped stdin pattern — we always want
    # the keystroke from the user's terminal, not the curl output.
    read -rp "    Press ENTER when ready (or Ctrl-C to skip)... " </dev/tty || return

    log "restarting yabai / skhd to pick up the consent"
    local svc
    for svc in yabai skhd; do
      command -v "$svc" >/dev/null 2>&1 || continue
      if "$svc" --restart-service >/dev/null 2>&1; then
        ok "$svc restarted"
      else
        warn "$svc restart failed — try: $svc --restart-service"
      fi
    done
  else
    warn "no tty — grant access manually, then:"
    dim "    yabai --restart-service && skhd --restart-service"
  fi
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
  post_install_window_manager
  log "done"
  dim "open a new shell to pick up your new \$SHELL/\$PATH"
}

main "$@"
