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

    ignores = [
      ".DS_Store"
      ".idea"
      ".vscode"
      "*.swp"
    ];
  };
}
