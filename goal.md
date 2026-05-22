# goal.md — what this repo is and how to think about it

> Read this before deciding *what* to do. Read `CLAUDE.md` for *how* to do it.

## Communication

用中文与用户交流。

## North Star

This is a **personal macOS environment, declared as a Nix flake**. Two
non-negotiables:

1. **Idempotent** — every change must converge the system to its declared
   state. Re-running `darwin-rebuild switch` is always safe, anytime.
2. **Declarative** — if a thing can be expressed in Nix, never write
   imperative code for it. Bash is allowed only in `install.sh`, and only
   for what bash uniquely can do (bootstrap before Nix exists).

## Project philosophy

- **Boring Technology** (Dan McKinley's talk) — pick the dullest solution
  that works. Nix-darwin + Home Manager is the dullest known good.
- **One concern per module** — `modules/home/zsh.nix` configures zsh and
  nothing else. Don't grow grab-bag files. A new tool with non-trivial
  config gets a new file under `modules/home/`.
- **Declarative > imperative** — any imperative bash, TS, or `command -v
  X && Y` logic outside `install.sh` is a smell. We previously rewrote
  the whole installer because the imperative approach kept growing
  workarounds; don't recreate it.

## External reality (authoritative artifacts)

Align proposals to these, not to me:

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

## Disagreement clause

If a request conflicts with the North Star or the philosophy above:

- Say so directly, in the first sentence of the reply.
- Quote the specific conflict (which rule, which artifact).
- Propose the declarative shape that does fit, even if it's more work.
- Do not soften with "you might want to consider" or "one option could be".

The artifacts above outrank my in-the-moment preference. If I'm asking for
something that drifts from them, I want to be told, not accommodated.
