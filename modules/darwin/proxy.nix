{ pkgs, ... }:

# Three coordinated mechanisms to get $HTTPS_PROXY through nix-darwin's
# activation pipeline, so brew bundle's `sudo -u $user -i` inner shell
# can reach github:
#
#   1. sudoers env_keep drop-in    — sudo preserves the var
#   2. /etc/zshenv.local sourcing  — login shells re-export it after sudo -i resets env
#   3. (HM activation, modules/home/proxy.nix) — launchctl setenv for re-switches
#
# (1) without (2) is not enough: `sudo -u $user -i` runs a login shell
# which resets env wholesale, env_keep notwithstanding. (2) without (1)
# is not enough either: a non-login sudo path skips zshenv.
#
# All three read from ~/.config/dotfiles/proxy.env (machine-local,
# written by install.sh). No proxy → all three are silent no-ops.

let
  sudoersFile = pkgs.writeText "dotfiles-proxy" ''
    Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
  '';
in
{
  ###
  ### (1) sudoers env_keep — installed with `install -m 440 -o root -g
  ### wheel` in preActivation so it's in place BEFORE the homebrew
  ### activation phase fires `sudo -u $user brew bundle`. (postActivation
  ### would write it too late on the first switch.)
  ###
  system.activationScripts.preActivation.text = ''
    /usr/bin/install -m 440 -o root -g wheel \
      ${sudoersFile} /etc/sudoers.d/dotfiles-proxy
  '';

  ###
  ### (2) /etc/zshenv.local — nix-darwin's generated /etc/zshenv ends
  ### with `[ -f /etc/zshenv.local ] && source /etc/zshenv.local`, so
  ### anything we drop here runs for every zsh login shell, including
  ### the inner shell spawned by `sudo -u $user -i` during brew bundle.
  ### The HOME used is the inner shell's HOME (i.e. lume's), so the
  ### path resolves correctly.
  ###
  environment.etc."zshenv.local".text = ''
    # Per-machine proxy, written by install.sh on first bootstrap.
    [ -f "$HOME/.config/dotfiles/proxy.env" ] && \
      . "$HOME/.config/dotfiles/proxy.env"
  '';
}
