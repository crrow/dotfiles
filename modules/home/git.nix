{ ... }:

{
  programs.git = {
    enable       = true;
    delta.enable = true;

    # As of home-manager 25.11, user{Name,Email} + extraConfig were
    # folded into a single `settings` tree that mirrors gitconfig
    # sections directly.
    settings = {
      user.name            = "crrow";
      user.email           = "hahadaxigua@gmail.com";
      init.defaultBranch   = "main";
      pull.ff              = "only";
      push.autoSetupRemote = true;
    };

    # HM warns when this is left at the legacy default. Off explicitly;
    # flip to true to have git stash credentials in the macOS Keychain.
    enableGitCredentialOSXKeychain = false;

    ignores = [
      ".DS_Store"
      ".idea"
      ".vscode"
      "*.swp"
    ];
  };
}
