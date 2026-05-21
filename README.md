# dotfiles

Personal dev environment. macOS first, Linux compatible. Driven by a single
TypeScript installer (`src/setup.ts`) running on Bun — no chezmoi, no bash logic.

## What's inside

- **Shell**: zsh + oh-my-zsh + [starship](https://starship.rs) prompt
- **Terminal**: [Ghostty](https://ghostty.org)
- **Multiplexer**: [zellij](https://zellij.dev)
- **Runtime manager**: [mise](https://mise.jdx.dev) (manages bun, node, …)
- **Installer**: bun + TypeScript (`src/setup.ts`)

## Layout

```
.
├── mise.toml             # pins bun for the installer itself
├── package.json
├── src/setup.ts          # the installer
└── home/                 # everything here is symlinked into $HOME
    ├── .zshrc
    └── .config/
        ├── ghostty/config
        ├── starship.toml
        ├── zellij/config.kdl
        └── mise/config.toml
```

Anything under `home/` is symlinked into `$HOME` preserving the relative path.
Existing files are backed up to `*.bak-<ts>` before being replaced.

## Bootstrap on a new machine

```sh
# 1. mise (only thing that has to come from outside)
command -v mise >/dev/null || curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# 2. Clone and enter
git clone https://github.com/crrow/dotfiles.git ~/code/personal/dotfiles
cd ~/code/personal/dotfiles

# 3. Install bun via mise, then run the TS installer
mise trust
mise install
bun install
bun run setup
```

Dry-run first if you want to see what would happen:

```sh
bun run setup:dry
```

## Day-to-day

Edit files under `home/` directly — they're the live source, the symlinks
point here. To add a new tool to the brew install list, edit `FORMULAE` /
`CASKS_DARWIN` in `src/setup.ts` and re-run `bun run setup`.
