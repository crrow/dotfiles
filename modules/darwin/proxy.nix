{ ... }:

# Static sudoers drop-in: env_keep for the proxy vars.
#
# Without this, sudo strips HTTPS_PROXY / etc out of the environment.
# That bites every `sudo …` inside nix-darwin activation (brew bundle,
# helper scripts) when the user is on a corporate proxy or behind the
# VM-test gateway. Drop-in (not a wholesale /etc/sudoers edit) so it's
# easy to remove and survives macOS updates that rewrite sudoers.
#
# Always present, no proxy → harmless: env_keep on absent vars is a
# no-op. Hence no toggle and no dependence on proxy.env existence.
{
  environment.etc."sudoers.d/dotfiles-proxy" = {
    text = ''
      Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
    '';
    mode = "0440";
  };
}
