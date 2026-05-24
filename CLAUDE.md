# CLAUDE.md — index

Single source of truth for AI assistants in this repo. `AGENTS.md`,
`GEMINI.md`, `.cursorrules`, `.windsurfrules` are symlinks to this file —
edit `CLAUDE.md`, never create those as separate files.

The same single-source pattern applies to harness configuration:
`.claude/` is canonical; `.codex/hooks/` is a symlink to
`.claude/hooks/` so Claude Code and Codex share one set of guard
scripts. Edit under `.claude/`, never duplicate into `.codex/`.

## Read first — the why

- [`goal.md`](./goal.md) — what this repo is (personal macOS Nix flake),
  the two non-negotiables (idempotent + declarative), the philosophy
  anchors (Boring Technology, one concern per module), authoritative
  artifacts to align proposals against, and the disagreement clause.
  Decisions get measured against this file.

## The how — skills (`.claude/skills/`)

Pick the skill whose description matches the task; it will guide the
edit, build, and switch.

- **`add-package`** — install a CLI tool, GUI app, or `programs.X`
  Home Manager module.
- **`update-flake`** — bump `flake.lock` safely (build before switch,
  abort cleanly on failure).
- **`test-on-fresh-vm`** — bootstrap this repo end-to-end on a clean
  macOS VM via lume. Use after invasive changes or before a release.
- **`dotfiles-dev`** — operating discipline that applies to every
  change: parallel-worktree workflow, `system.defaults` edits,
  verification rhythm, drift anti-patterns, Nix + Bash house style.

## Communication

用中文与用户交流。
