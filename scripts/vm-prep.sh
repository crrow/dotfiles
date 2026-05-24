#!/usr/bin/env bash
#
# Runs *inside* the lume test VM. Invoked by `just _vm-prep` over SSH,
# base64-piped in (the shared-mount path is cached aggressively by the
# guest, so host edits weren't visible).
#
# Two VM-only accommodations install.sh can't do on its own:
#   1. passwordless+!authenticate sudo (install.sh assumes a real Mac
#      where sudo will prompt the user)
#   2. /etc/zshenv that pre-exports HTTPS_PROXY and DOTFILES_DIR — the
#      VM equivalent of "user typed `export HTTPS_PROXY=…` before
#      curl|bash" on a real Mac. With this in place, the curl|bash
#      command run in the VM is byte-identical to the one a real-Mac
#      user runs (no hidden wrapper file), and any shell — vm-bootstrap's
#      osascript, `lume ssh`, a VNC Terminal — sees the same env.

set -euo pipefail

proxy="${1:?usage: vm-prep.sh <proxy-url>}"

# 1. sudoers — VM-only escape hatches.
#    macOS sudo -v ignores NOPASSWD (always wants a password); !authenticate
#    lifts that. env_keep preserves proxy vars across any sub-sudo that
#    didn't opt in via --preserve-env. Only safe in a throwaway VM.
sudoers_content=$(
  cat <<'EOF'
Defaults !authenticate
lume ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
EOF
)
printf '%s\n' "$sudoers_content" >/tmp/sudoers-add
echo lume | sudo -S install -m 440 -o root -g wheel /tmp/sudoers-add /etc/sudoers.d/dotfiles-test
rm /tmp/sudoers-add

# 2. /etc/gitconfig — disable libgit2's CVE-2022-24765 ownership check.
#    The shared mount (/Volumes/My Shared Files/) is owned by the host
#    user's UID, not lume's, so nix's libgit2-backed flake-input fetcher
#    refuses to read it ("repository path is not owned by current user").
#    A throwaway VM can trust everything.
gitconfig_content="[safe]
	directory = *"
printf '%s\n' "$gitconfig_content" >/tmp/gitconfig-add
echo lume | sudo -S install -m 644 -o root -g wheel /tmp/gitconfig-add /etc/gitconfig
rm /tmp/gitconfig-add

# 3. /etc/zshenv — proxy + DOTFILES_DIR for every shell in the VM.
#    Sourced before every zsh invocation (interactive, login, ssh
#    one-shot), so the curl|bash bootstrap is identical to what a real-
#    Mac user runs. DOTFILES_DIR points at the shared mount so install.sh
#    skips its fetch step and tests the host's live working tree.
zshenv_content="export HTTPS_PROXY=\"$proxy\"
export HTTP_PROXY=\"$proxy\"
export ALL_PROXY=\"$proxy\"
export https_proxy=\"$proxy\"
export http_proxy=\"$proxy\"
export all_proxy=\"$proxy\"
export DOTFILES_DIR=\"/Volumes/My Shared Files\""
printf '%s\n' "$zshenv_content" >/tmp/zshenv-add
echo lume | sudo -S install -m 644 -o root -g wheel /tmp/zshenv-add /etc/zshenv
rm /tmp/zshenv-add

echo 'VM-test accommodations applied.'
