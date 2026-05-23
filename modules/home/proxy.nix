{ lib, ... }:

# User-launchd proxy propagation.
#
# Why this exists: nix-darwin's activation runs `sudo -u $USER -i …`
# (login shell) for things like brew bundle. sudo's env-strip plus -i
# means HTTPS_PROXY exported in install.sh is gone by the time the
# inner shell reaches out to github. `launchctl setenv` plants the
# vars in the user's launchd session so any launchd-spawned subshell
# inherits them — closes the env-stripping hole that sudo
# --preserve-env can't reach.
#
# Runs every `darwin-rebuild switch` (idempotent — `launchctl setenv`
# overwrites silently). No-op on machines without a proxy.

{
  home.activation.proxyLaunchd =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      proxy_env="$HOME/.config/dotfiles/proxy.env"
      [ -f "$proxy_env" ] || exit 0

      # shellcheck disable=SC1090
      . "$proxy_env"
      for k in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy \
               ALL_PROXY all_proxy NO_PROXY no_proxy; do
        v="$(eval printf '%s' "\''${$k:-}")"
        [ -n "$v" ] && $DRY_RUN_CMD /bin/launchctl setenv "$k" "$v"
      done
    '';
}
