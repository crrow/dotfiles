{ ... }:

# Determinate Nix's daemon plist is root-owned, launchd-managed, and
# NOT under nix-darwin's purview (`nix.enable = false` cedes daemon
# ownership to Determinate). But the daemon's libcurl still needs
# HTTPS_PROXY in env to reach cache.nixos.org and github through a
# proxy. The plist won't auto-pick up env from our shells, so we
# inject it at activation time and restart the daemon.
#
# Idempotent: Delete-then-Add for each key. No-op when no proxy is set.

let
  plist = "/Library/LaunchDaemons/systems.determinate.nix-daemon.plist";

  injectScript = ''
    # shellcheck source=/dev/null
    if [ -f "$HOME/.config/dotfiles/proxy.env" ]; then
      . "$HOME/.config/dotfiles/proxy.env"
    fi
    [ -z "''${HTTPS_PROXY:-}" ] && exit 0
    [ -f "${plist}" ] || exit 0

    echo "[nix-daemon-proxy] injecting proxy into Determinate plist…" >&2
    /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "${plist}" 2>/dev/null || true
    for k in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy; do
      v=$(eval "echo \''${''${k}:-}")
      [ -z "$v" ] && continue
      /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$k" "${plist}" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$k string $v" "${plist}"
    done

    # `kickstart -k` doesn't pick up plist env changes — need a full
    # bootout/bootstrap. KeepAlive may respawn past bootout, kill
    # stragglers by name to be sure.
    /bin/launchctl bootout system "${plist}" 2>/dev/null || true
    /usr/bin/pkill -9 -f nix-daemon 2>/dev/null || true
    sleep 1
    /bin/launchctl bootstrap system "${plist}"
    sleep 3
  '';
in
{
  system.activationScripts.nixDaemonProxy = {
    text = injectScript;
  };
}
