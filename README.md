# dotfiles

Personal macOS environment as a [Nix flake](https://nixos.wiki/wiki/Flakes).
[nix-darwin](https://github.com/LnL7/nix-darwin) declares system-level state
(macOS defaults, Homebrew casks); [Home Manager](https://github.com/nix-community/home-manager)
declares the user-level stuff (CLI tools, zsh, prompt, dotfiles).

Idempotent by construction — every run converges the system toward the
declared state. Re-running `darwin-rebuild switch` is always safe.

## What's inside

- **System** (`modules/darwin.nix`): macOS defaults (Dock, Finder, key repeat,
  …), Homebrew bridge for casks (Ghostty)
- **User** (`modules/home.nix`): zsh + oh-my-zsh + [starship](https://starship.rs),
  [zellij](https://zellij.dev), [mise](https://mise.jdx.dev), git (with delta),
  fzf, bat, eza, fd, ripgrep
- **Terminal**: [Ghostty](https://ghostty.org) (cask) with config in
  `modules/home.nix`

## Bootstrap on a new macOS

One line, from a fresh user shell:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
```

What happens:

1. `install.sh` installs [Determinate Nix](https://determinate.systems/nix) if
   `nix` isn't already on PATH.
2. Clones this repo to `~/code/personal/dotfiles` (uses `nix run nixpkgs#git`
   so no Xcode CLT detour is needed).
3. Runs `darwin-rebuild switch --flake .` — Nix builds the entire system
   profile (CLI tools, Home Manager links, Homebrew casks) and activates it.

Open a new shell when it's done. The login shell is now Nix-managed zsh with
mise + starship + OMZ wired up.

Env knobs: `DOTFILES_DIR` (default `~/code/personal/dotfiles`),
`DOTFILES_REF` (default `main`).

## Day-to-day

```sh
cd ~/code/personal/dotfiles
$EDITOR modules/home.nix              # change something
darwin-rebuild switch --flake .        # apply

nix flake update                       # bump pinned inputs
darwin-rebuild switch --flake .
```

`darwin-rebuild switch` will roll back automatically if activation fails —
nothing partial gets left on disk.

## Layout

```
.
├── install.sh           # bash bootstrap: Determinate Nix → clone → switch
├── flake.nix            # entry point: inputs (nixpkgs / nix-darwin / HM) + outputs
├── flake.lock           # pinned input revisions (committed)
├── modules/
│   ├── darwin.nix       # nix-darwin: system defaults + Homebrew casks
│   └── home.nix         # Home Manager: user CLI + zsh / starship / zellij / git
├── Justfile             # local VM control for testing on a clean macOS
├── .claude/skills/      # how Claude verifies bootstrap on a fresh VM
└── README.md
```

## Testing on a fresh macOS VM

`Justfile` spins up a vanilla macOS VM via
[lume](https://github.com/trycua/cua):

```sh
just baseline   # one-off ~22 GB image pull
just vm-up      # clone baseline → start → wait for SSH (VNC pops automatically)
just vm-ssh     # interactive shell (creds: lume / lume)
just vm-vnc     # re-open VNC if you closed it
just vm-down    # stop + delete the working VM
```

Inside the VM you'd run the same one-liner from "Bootstrap on a new macOS"
above. See `.claude/skills/test-on-fresh-vm/SKILL.md` for the full
end-to-end verification workflow including known gotchas (lume NAT DNS
quirks, proxy setup).
