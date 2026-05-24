{ pkgs, lib, ... }:

# Declarative VS Code: the app, the extension set, and (room for)
# settings/keybindings. Extensions are pulled from the Microsoft
# Marketplace via the `nix-vscode-extensions` overlay, falling back to
# Open VSX, so the full long tail is reachable without per-extension
# sha256 babysitting.
#
# Lookup is defensive: any "publisher.extension" id that exists in
# neither registry is dropped silently. This way a renamed or
# delisted extension doesn't take down the whole switch; you find out
# from `code --list-extensions` afterward and fix the id.
#
# To refresh the extension set:
#   1. install/remove via the VS Code UI on this machine,
#   2. `code --list-extensions` to see the new set,
#   3. mirror the diff into the list below,
#   4. `nix flake update nix-vscode-extensions` for newer versions,
#   5. `darwin-rebuild build --flake .` then `switch`.

let
  vsm = pkgs.vscode-marketplace or { };
  ovs = pkgs.open-vsx          or { };

  # lookupExt :: "publisher.ext-name" -> derivation | null
  # Marketplace first (broader catalog), then Open VSX, then give up.
  # Wrapped in tryEval so extensions that nixpkgs has marked unsupported
  # on the current platform (e.g. ms-vscode.cpptools on aarch64-darwin)
  # are silently dropped instead of aborting evaluation.
  lookupExt = id:
    let
      parts = lib.splitString "." id;
      pub   = builtins.head parts;
      # Extensions can have dots in the name (rare), rejoin the tail.
      name  = lib.concatStringsSep "." (builtins.tail parts);
      pickFrom = src:
        let p = src.${pub} or null; in
        if p != null && p ? ${name}
        then let t = builtins.tryEval p.${name};
             in if t.success then t.value else null
        else null;
      fromMarketplace = pickFrom vsm;
      fromOpenVsx     = pickFrom ovs;
    in
      if fromMarketplace != null then fromMarketplace
      else fromOpenVsx;

  extensionIds = [
    # --- editor / themes / icons ---
    "bwya77.islands-dark"
    "catppuccin.catppuccin-vsc"
    "hardhacker.hard-hacker-theme"
    "mateocerquetella.xcode-12-theme"
    "michalpopek.dayfox-vsc"
    "monokai.theme-monokai-pro-vscode"
    "mvllow.rose-pine"
    "pkief.material-icon-theme"
    "robbowen.synthwave-vscode"
    "subframe7536.custom-ui-style"
    "tinkertrain.theme-panda"

    # --- editing / UX ---
    "aaron-bond.better-comments"
    "editorconfig.editorconfig"
    "formulahendry.code-runner"
    "streetsidesoftware.code-spell-checker"
    "techer.open-in-browser"
    "vscodevim.vim"
    "wakatime.vscode-wakatime"
    "wayou.vscode-todo-highlight"

    # --- git ---
    "codezombiech.gitignore"
    "donjayamanne.githistory"
    "eamodio.gitlens"
    "mhutchie.git-graph"
    "waderyan.gitblame"

    # --- AI assistants ---
    "anthropic.claude-code"
    "github.copilot-chat"
    "openai.chatgpt"

    # --- markdown / docs / data ---
    "bierner.markdown-mermaid"
    "davidanson.vscode-markdownlint"
    "eriklynd.json-tools"
    "mechatroner.rainbow-csv"
    "meezilla.json"
    "tomoki1207.pdf"

    # --- nix ---
    "bbenoist.nix"

    # --- python ---
    "batisteo.vscode-django"
    "charliermarsh.ruff"
    "donjayamanne.python-environment-manager"
    "donjayamanne.python-extension-pack"
    "kevinrose.vsc-python-indent"
    "ms-python.debugpy"
    # ms-python.python pulls in python3.13-jedi-language-server, which
    # in current nixpkgs (jedi 0.20.0) fails its runtime-deps check
    # (constraint jedi<0.20). Re-enable after upstream bump.
    # "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-python.vscode-python-envs"
    "njpwerner.autodocstring"
    "wholroyd.jinja"

    # --- rust / go / zig / swift / bun ---
    "golang.go"
    "oven.bun-vscode"
    "rust-lang.rust-analyzer"
    "swiftlang.swift-vscode"
    "ziglang.vscode-zig"

    # --- c / c++ / llvm ---
    "franneck94.c-cpp-runner"
    "llvm-vs-code-extensions.lldb-dap"
    "ms-vscode.cmake-tools"
    # ms-vscode.cpptools{,-extension-pack,-themes} and cpp-devtools were
    # removed on aarch64-darwin in nixpkgs (Microsoft only ships x86_64
    # binaries with restrictive license). Use clangd or vadimcn.vscode-lldb
    # for native dev on Apple Silicon.
    "ms-vscode.makefile-tools"
    # vadimcn.vscode-lldb builds codelldb from source via cargo — pulls
    # in rustc + llvm + vendor dirs (~2.5 GB). Skipped on disk-tight VMs
    # for now; use llvm-vs-code-extensions.lldb-dap instead if needed.
    # "vadimcn.vscode-lldb"

    # --- java / jvm ---
    "redhat.java"
    "vscjava.vscode-gradle"
    "vscjava.vscode-java-debug"
    "vscjava.vscode-java-dependency"
    "vscjava.vscode-java-pack"
    "vscjava.vscode-java-test"
    "vscjava.vscode-maven"

    # --- web / frontend ---
    "dbaeumer.vscode-eslint"

    # --- typst ---
    "myriad-dreamin.tinymist"
    "nvarner.typst-lsp"

    # --- protobuf / yaml / toml / just / earthly ---
    "drblury.protobuf-vsc"
    "earthly.earthfile-syntax-highlighting"
    "nefrob.vscode-just-syntax"
    "redhat.vscode-yaml"
    "tamasfe.even-better-toml"

    # --- containers / devops ---
    "4ops.packer"
    "github.vscode-github-actions"
    "ms-azuretools.vscode-containers"
    "ms-azuretools.vscode-docker"

    # --- remote ---
    "ms-vscode-remote.remote-containers"
    "ms-vscode-remote.remote-ssh"
    "ms-vscode-remote.remote-ssh-edit"
    "ms-vscode-remote.remote-wsl"
    "ms-vscode-remote.vscode-remote-extensionpack"
    "ms-vscode.remote-explorer"
    "ms-vscode.remote-server"

    # --- testing / misc ---
    "vtenentes.bdd"
  ];
in
{
  programs.vscode = {
    enable = true;

    # Keep the HM-managed extension set — that's what nix-vscode-extensions
    # is for. settings + keybindings live as plain JSON files under
    # home/dot_config/Code/User/ so they're usable outside Nix too.
    profiles.default = {
      extensions = lib.filter (e: e != null) (map lookupExt extensionIds);
    };
  };

  # macOS VS Code reads config from ~/Library/Application Support/Code/User/,
  # NOT ~/.config/Code. Symlink both — chezmoi-source under home/dot_config/
  # Code/User/ stays the source-of-truth path. HM lets us put files anywhere
  # under $HOME so the macOS path works directly.
  home.file."Library/Application Support/Code/User/settings.json".source =
    ../../home/dot_config/Code/User/settings.json;
  home.file."Library/Application Support/Code/User/keybindings.json".source =
    ../../home/dot_config/Code/User/keybindings.json;
}
