{ ... }:

{
  programs.git = {
    enable = true;

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

  # delta moved out of programs.git in HM ≥ 25.11; live as a top-level
  # module that opt-in wires itself into git via the explicit
  # `enableGitIntegration` flag (the implicit wiring is deprecated).
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}
