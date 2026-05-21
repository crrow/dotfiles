{ ... }:

{
  programs.git = {
    enable       = true;
    userName     = "crrow";
    userEmail    = "hahadaxigua@gmail.com";
    delta.enable = true;

    extraConfig = {
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
