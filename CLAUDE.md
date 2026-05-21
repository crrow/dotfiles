# CLAUDE.md — crrow/dotfiles development guide

This file is the single source of truth for AI assistants working in this
repo. `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules` are all
symlinks to this file.

## Communication

- 用中文与用户交流。

## North Star

This is a **personal macOS environment, declared as a Nix flake**. Two
non-negotiables:

1. **Idempotent** — every change must converge the system to its declared
   state. Re-running `darwin-rebuild switch` is always safe, anytime.
2. **Declarative** — if a thing can be expressed in Nix, never write
   imperative code for it. Bash is allowed only in `install.sh`, and only
   for what bash uniquely can do (bootstrap before Nix exists).

If a request conflicts with these, **say so directly**. Don't soften with
"you might want to consider"; quote the conflict and propose the
declarative shape.

## External reality (authoritative artifacts)

- `flake.nix` — inputs (nixpkgs / nix-darwin / home-manager) + the
  `darwinConfigurations.default` output
- `modules/darwin.nix` — system state: macOS defaults, Homebrew casks
- `modules/home/` — user state, one file per concern (zsh, git, starship,
  zellij, ghostty, mise); `default.nix` is the entry that imports them
- `install.sh` — minimal bootstrap (Determinate Nix → clone → switch),
  with a PID-based lock at `$TMPDIR/crrow-dotfiles-install.lock`
- `Justfile` — local lume VM control, for testing on a clean macOS
- `.claude/skills/test-on-fresh-vm/SKILL.md` — proven VM-based
  verification workflow with all the gotchas captured

## Project philosophy

- **Boring Technology** (Dan McKinley) — pick the dullest solution that
  works. Nix-darwin + Home Manager is the dullest known good.
- **One concern per module** — `modules/home/zsh.nix` configures zsh and
  nothing else. Don't grow grab-bag files. A new tool with non-trivial
  config gets a new file under `modules/home/`.
- **Declarative > imperative** — any imperative bash, TS, or `command -v
  X && Y` logic outside `install.sh` is a smell. We previously rewrote
  the whole installer because the imperative approach kept growing
  workarounds; don't recreate it.

## Workflow

**To add a CLI tool** (e.g., `htop`):
1. Add `htop` to `home.packages` in `modules/home/default.nix`.
2. `darwin-rebuild switch --flake .`

**To add a GUI app** (e.g., `obsidian`):
1. Add `"obsidian"` to `homebrew.casks` in `modules/darwin.nix`.
2. `darwin-rebuild switch --flake .`

**To configure a program** (e.g., bat themes):
1. Look up the Home Manager `programs.X` options on
   <https://home-manager-options.extranix.com>.
2. Create `modules/home/<name>.nix` if there isn't one yet, and add it to
   `imports` in `modules/home/default.nix`.
3. `darwin-rebuild switch --flake .`

**To change a macOS default** (e.g., autohide Dock):
1. Find the `defaults write` key — `defaults read NSGlobalDomain` lists
   them, or grep the nix-darwin source.
2. Add to `system.defaults` in `modules/darwin.nix`.
3. `darwin-rebuild switch --flake .`

**To verify on a fresh macOS before pushing**:
- Invoke the `test-on-fresh-vm` skill (see `.claude/skills/`).

## Verification

Before reporting a change complete:

- `nix flake check` — catches syntax + module-evaluation errors fast.
- `darwin-rebuild build --flake .` — full evaluation, no activation.
- For invasive changes (new module, system-defaults edit, cask add/remove):
  run the VM skill to make sure a fresh-mac bootstrap still works.

## What NOT to do

- Do NOT add bash logic outside `install.sh` for anything Nix can express.
  Even simple-looking imperative loops grow workarounds. (Past evidence:
  the brew/bun/TS installer that this repo used to be.)
- Do NOT commit a `flake.lock` bump without running `darwin-rebuild
  build --flake .` first. A bad nixpkgs revision rebuilds the world.
- Do NOT delete `$TMPDIR/crrow-dotfiles-install.lock` blindly. Check
  `kill -0 $(cat $TMPDIR/.../pid)` to see if a real installer is
  running; `install.sh` already auto-clears stale locks.
- Do NOT bypass `darwin-rebuild` with a manual `brew install` or
  `defaults write`. Those mutations drift out of the declared state and
  will be undone on the next switch.
- Do NOT create AGENTS.md / GEMINI.md / .cursorrules / .windsurfrules as
  separate files — they are symlinks to this one. Edit `CLAUDE.md`.

## Bash style (for the rare cases we touch `install.sh`)

Follow [Google Shell Style Guide][gssg] for the parts that apply on macOS:

- `#!/usr/bin/env bash` shebang, `set -euo pipefail`, `IFS=$'\n\t'`
- `readonly` for constants, `local` for function variables
- Functions are lowercase_with_underscores, one verb per name
- `[[ ]]` not `[ ]`; always quote `"$var"`
- `printf` not `echo` for anything with interpolation
- Cleanup via `trap … EXIT INT TERM`, never via "and at the end…"
- Every script must pass `shellcheck` clean

[gssg]: https://google.github.io/styleguide/shellguide.html

## Nix style

- `flake.nix` stays lean — inputs/outputs wiring, nothing else. Real
  config lives in `modules/`.
- `inputs.X.follows = "nixpkgs"` to dedupe nixpkgs revisions across
  flake inputs.
- One concern per module file. If a file is approaching 80 lines and
  covers more than one program, split it.
- Comments explain *why*, not *what*. The attribute names are the
  what. The comment is "we need this because X breaks otherwise".
- `lib.mkForce` only when consciously overriding upstream; never as a
  band-aid.
