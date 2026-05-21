---
name: add-package
description: |
  Use when the user asks to add a new tool / app to the dotfiles —
  "install htop", "add Obsidian", "I want to use ripgrep", or any
  variation of "add X to my environment".

  This skill picks the right surface (Home Manager package, Home Manager
  `programs.X` module, or Homebrew cask), edits the relevant module
  file, builds to verify, and switches to apply. Stops at the build
  step if anything fails, leaving the working tree clean.

  Do NOT use for system defaults (Dock, Finder, key repeat) — those go
  through `system.defaults` in `modules/darwin.nix`, not the package
  pipeline.
---

# Add a package

Three surfaces, decided by what the user is installing:

| Tool type                | Surface                                  | File                              |
| ------------------------ | ---------------------------------------- | --------------------------------- |
| CLI binary, no config    | `home.packages` in HM                    | `modules/home/default.nix`        |
| CLI/TUI with config      | `programs.X` HM module                   | `modules/home/<name>.nix` (new)   |
| GUI app (signed, /Apps)  | Homebrew cask                            | `modules/darwin.nix` (`casks`)    |

When in doubt, **prefer the Home Manager `programs.X` module** over
plain `home.packages` — it integrates config and shell completions.

## Workflow

### 1. Resolve the package name

- HM module first: search <https://home-manager-options.extranix.com>
  for `programs.<name>`. If it exists, use that surface — even if you
  don't need its config options yet.
- Plain package: `nix search nixpkgs <name>` to confirm the attribute
  path. (For darwin: `nix search nixpkgs#legacyPackages.aarch64-darwin.<name>`.)
- Cask: search <https://formulae.brew.sh/cask>. Use the cask token
  (lowercase, hyphenated), not the display name.

### 2. Edit the right file

**CLI binary, no config** — add to `home.packages`:

```nix
# modules/home/default.nix
home.packages = with pkgs; [
  bat
  eza
  htop      # ← new
  …
];
```

**CLI with config** — new file under `modules/home/`:

```nix
# modules/home/htop.nix
{ ... }:
{
  programs.htop = {
    enable = true;
    settings.show_program_path = false;
  };
}
```

Then add it to the imports list:

```nix
# modules/home/default.nix
imports = [
  ./zsh.nix
  …
  ./htop.nix    # ← new
];
```

**GUI cask** — add to `homebrew.casks`:

```nix
# modules/darwin.nix
homebrew.casks = [
  "ghostty"
  "obsidian"   # ← new
];
```

### 3. Build first, switch second

Always build before switch. Build catches eval errors fast and doesn't
touch the live system.

```sh
cd ~/code/personal/dotfiles
darwin-rebuild build --flake .   # eval + build, no activation
darwin-rebuild switch --flake .  # activate
```

If `build` fails: read the error. The most common ones are misspelled
attribute paths (`htopp`) or missing `pkgs.` prefix when using the
`{ pkgs, ... }:` form.

### 4. Verify

CLI: open a new shell, run `<binary> --version`.
GUI cask: `ls /Applications/<Name>.app` — Homebrew installs into
`/Applications`, not `~/Applications`.

## Don't

- Don't run `nix-env -i` or `brew install` directly. Those install
  outside the declared state and get clobbered on the next
  `darwin-rebuild switch` (`cleanup = "uninstall"` for casks).
- Don't add casks for things that have a working Nix package — nixpkgs
  is the canonical source; casks are reserved for GUI apps that Nix
  can't realistically build on macOS (signed, sandboxed, dock-integrated).
- Don't bundle multiple unrelated tools into one commit. One tool, one
  commit, one easy revert.
