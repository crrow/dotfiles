# dotfiles

Personal dev environment. macOS first. Driven by a tiny bash bootstrap
(`install.sh`) that exists only to install Homebrew + bun on a vanilla
machine — every other step is TypeScript.

## What's inside

- **Shell**: zsh + oh-my-zsh + [starship](https://starship.rs) prompt
- **Terminal**: [Ghostty](https://ghostty.org)
- **Multiplexer**: [zellij](https://zellij.dev)
- **Runtime manager**: [mise](https://mise.jdx.dev) (for bun, node, …)
- **Installer**: bun + TypeScript (`scripts/install.ts` + `src/setup.ts`)

## Layout

```
.
├── install.sh           # ~20-line bash bootstrap (brew + bun → TS)
├── scripts/
│   ├── install.ts       # brew install git, clone repo, hand off to setup
│   └── vm-*.ts          # local VM control for testing on a clean macOS
├── src/setup.ts         # installs formulae/casks, OMZ, symlinks, chsh
├── mise.toml            # pins bun for project tooling
└── home/                # everything here is symlinked into $HOME
    ├── .zshrc
    └── .config/
        ├── ghostty/config
        ├── starship.toml
        ├── zellij/config.kdl
        └── mise/config.toml
```

Anything under `home/` is symlinked into `$HOME` preserving the relative
path. Existing files are backed up to `*.bak-<ts>` before being replaced.

## Bootstrap on a new macOS

One line, from a fresh user shell. You'll be prompted for your sudo
password once (Homebrew needs it):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
```

That's it. What happens, in order:

1. `install.sh` installs Homebrew (which installs Xcode Command Line
   Tools non-interactively) and `bun`.
2. It fetches `scripts/install.ts` and execs it under bun.
3. `scripts/install.ts` `brew install`s git, clones this repo to
   `~/code/personal/dotfiles`, then runs `bun install` + `bun run setup`.
4. `src/setup.ts` installs the rest of the formulae and casks, sets up
   oh-my-zsh + plugins, symlinks everything under `home/` into `$HOME`,
   and switches your login shell to brew zsh.

Open a new shell when it's done.

Env knobs: `DOTFILES_DIR` (default `~/code/personal/dotfiles`),
`DOTFILES_REF` (default `main`).

## Day-to-day

Edit files under `home/` directly — they're the live source, the symlinks
point here. To add a new tool, edit `FORMULAE` / `CASKS_DARWIN` in
`src/setup.ts` and re-run `bun run setup`.

To re-run the whole bootstrap against a different ref:

```sh
DOTFILES_REF=my-branch /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
```

Dry-run setup.ts only (skip brew/cask installs, just show what would symlink):

```sh
bun run setup:dry
```

## Testing on a fresh macOS VM

`Justfile` has targets that spin up a vanilla macOS VM via
[lume](https://github.com/trycua/cua) and let you verify the bootstrap
end-to-end. See the recipes (`just`) and the skill at
`.claude/skills/test-on-fresh-vm/` for the proven workflow + gotchas.
