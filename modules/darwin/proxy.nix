{ pkgs, lib, ... }:

# Proxy plumbing — owns every system file that needs the proxy value
# so it propagates through every sub-process nix-darwin's activation
# spawns. Reads ~/.config/dotfiles/proxy.env (machine-local, written
# by install.sh on first bootstrap).
#
# What we own:
#   /etc/sudoers.d/dotfiles-proxy  — env_keep for sudo -u user
#   /etc/gitconfig                 — http.proxy / https.proxy for `brew tap`
#   /etc/curlrc                    — proxy = ... for `brew fetch <formula>`
#   /etc/zshenv.local              — sourced by every login shell
#
# Why so many places: nix-darwin's activate invokes brew bundle via
# `sudo --preserve-env=PATH --user=$USER env HOMEBREW_NO_AUTO_UPDATE=1
#  brew bundle …`. The --preserve-env=PATH whitelist would strip
# HTTPS_PROXY without our sudoers env_keep. Even with env, brew's
# `curl --disable` ignores ~/.curlrc but env vars still apply — so
# both /etc/curlrc and env propagation are needed for full coverage.
# git clone's tap fetch reads /etc/gitconfig regardless of env.
#
# All write steps live under a NEW activation phase `proxyConfig`,
# which `homebrew.deps` depends on, so the files are in place BEFORE
# brew bundle runs on the very first switch. Setting them in
# preActivation isn't enough — nix-darwin places the entry late in
# the activate script in practice.

let
  proxyEnv = "$HOME/.config/dotfiles/proxy.env";

  # Single shell block reused across activationScripts. Reads proxy.env
  # if present, then re-writes each system file with the value (or a
  # no-proxy stub if the file isn't there). Safe to run on every switch.
  writeProxySystemConfig = ''
    # shellcheck source=/dev/null
    if [ -f "${proxyEnv}" ]; then
      . "${proxyEnv}"
    else
      HTTPS_PROXY=""
    fi

    # /etc/sudoers.d/dotfiles-proxy — always present. env_keep is a
    # no-op on absent vars, so this is safe even without a proxy.
    sudoers=$(/usr/bin/mktemp -t dotfiles-proxy)
    printf '%s\n' \
      'Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"' \
      >"$sudoers"
    /usr/bin/install -m 440 -o root -g wheel \
      "$sudoers" /etc/sudoers.d/dotfiles-proxy
    /bin/rm -f "$sudoers"

    if [ -n "$HTTPS_PROXY" ]; then
      # /etc/gitconfig — brew tap → git clone reads this regardless of env.
      /usr/bin/git config --system http.proxy  "$HTTPS_PROXY"
      /usr/bin/git config --system https.proxy "$HTTPS_PROXY"

      # /etc/curlrc — last-resort proxy for any curl invocation that
      # doesn't carry env (brew passes `--disable` to skip curlrc, but
      # env still applies; this is for everything else).
      printf 'proxy = "%s"\n' "$HTTPS_PROXY" >/etc/curlrc
      /bin/chmod 0644 /etc/curlrc
    else
      # No proxy: clean up so we don't leave stale config.
      /usr/bin/git config --system --unset-all http.proxy  2>/dev/null || true
      /usr/bin/git config --system --unset-all https.proxy 2>/dev/null || true
      /bin/rm -f /etc/curlrc
    fi
  '';
in
{
  ###
  ### /etc/zshenv.local — pulled in by nix-darwin's generated /etc/zshenv
  ### at the end (`[ -f /etc/zshenv.local ] && source /etc/zshenv.local`).
  ### Sources proxy.env so every login shell — including the inner one
  ### spawned by `sudo -u user -i` during HM activation — picks up the
  ### proxy after env-strip.
  ###
  environment.etc."zshenv.local".text = ''
    # Per-machine proxy, written by install.sh on first bootstrap.
    [ -f "$HOME/.config/dotfiles/proxy.env" ] && \
      . "$HOME/.config/dotfiles/proxy.env"
  '';

  ###
  ### preActivation.text runs early in nix-darwin's activate script,
  ### before the homebrew phase. lib.mkBefore puts our text at the
  ### very top of the preActivation block (multiple modules contribute
  ### text — mkBefore/default/mkAfter set ordering within the merge).
  ###
  ### nix-darwin's system.activationScripts submodule only has .text;
  ### there's no .deps field (that's NixOS's DAG, not nix-darwin's).
  ### So we can't depend on `homebrew`; instead we rely on phase order
  ### (preActivation → ... → homebrew → postActivation).
  ###
  system.activationScripts.preActivation.text = lib.mkBefore writeProxySystemConfig;
}
