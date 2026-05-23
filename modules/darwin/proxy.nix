{ pkgs, ... }:

# sudoers env_keep drop-in for proxy vars.
#
# Why activation script and not `environment.etc."sudoers.d/foo"`:
# nix-darwin's environment.etc has no .mode option, and `visudo` rejects
# any sudoers file that isn't 0440 root:wheel. Easiest reliable path is
# to install the rendered file with `install -m 440 -o root -g wheel`
# in postActivation.
#
# Without this, sudo strips HTTPS_PROXY / etc out of the environment,
# breaking every `sudo …` inside nix-darwin activation (brew bundle,
# helper scripts) when the user is on a corporate proxy or behind the
# VM-test gateway.
#
# Always present, no proxy → harmless: env_keep on absent vars is a
# no-op. Hence no toggle and no dependence on proxy.env existence.

let
  sudoersFile = pkgs.writeText "dotfiles-proxy" ''
    Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
  '';
in
{
  system.activationScripts.postActivation.text = ''
    /usr/bin/install -m 440 -o root -g wheel \
      ${sudoersFile} /etc/sudoers.d/dotfiles-proxy
  '';
}
