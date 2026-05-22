---
name: dotfiles-dev
description: |
  Use when developing inside this dotfiles repo and the work doesn't fall
  under one of the more specific skills. Covers the operating discipline
  that applies to every change here: parallel-agent worktree workflow,
  the `system.defaults` (macOS defaults) edit path, the verification
  rhythm before reporting work complete, drift anti-patterns to avoid,
  and the Nix + Bash house style.

  Trigger when: editing `modules/*.nix` or `install.sh`, starting work on
  a new feature, preparing to commit, opening a worktree, or any time the
  user mentions `darwin-rebuild`, `flake.lock`, `.worktrees/`, "verify",
  or "drift". Read this *with* `goal.md` (the why); this file is the how.

  Use the more specific skill when it applies:
  - Add a CLI tool / GUI app / programs.X module → `add-package`
  - Bump `flake.lock` → `update-flake`
  - Clean-VM bootstrap verification → `test-on-fresh-vm`
---

# dotfiles-dev — operating manual

The decisions this file shapes are mostly mechanical (commands, paths,
formatting). For the judgment calls — when a request conflicts with the
flake's declarative model, when to push back — see `goal.md`.

## Parallel work via worktrees

Multiple agents can work on this repo in parallel as long as no two of
them share the same checkout. Rules, enforced by
`.claude/hooks/worktree-guard.sh`:

- **Never `git checkout -b` / `git switch -c` on the main worktree.**
  The main checkout is shared; switching its HEAD breaks every other
  agent reading it. The hook blocks this.
- **Every feature/issue gets its own worktree** under `.worktrees/`:
  ```
  git worktree add .worktrees/<slug> -b <slug>
  cd .worktrees/<slug>
  ```
  `.worktrees/` is gitignored. Clean up with
  `git worktree remove .worktrees/<slug>` after merging.
- **Worktrees may `build`, never `switch`.** `darwin-rebuild switch`
  has global side effects (`/run/current-system`, brew bundle); two
  worktrees racing switch will clobber each other. Inside `.worktrees/*`
  the hook blocks `switch` — use `darwin-rebuild build --flake .` and
  `nix flake check` for verification. Activation happens on main, after
  merge.
- The same hook allows `git checkout main`, `git checkout origin/...`,
  and `git checkout -- <file>` everywhere, so file-level restores and
  returning to main still work.

## Changing a macOS default

(Anything `system.defaults` covers — Dock, Finder, keyboard, screenshots…)

1. Find the `defaults write` key — `defaults read NSGlobalDomain` lists
   them, or grep the nix-darwin source.
2. Add the attribute to `system.defaults` in `modules/darwin.nix`.
3. `darwin-rebuild switch --flake .` (on main).

Do not run `defaults write` by hand — `drift-guard.sh` blocks it, and
even if it didn't, the next `switch` would clobber the manual change.

## Verification rhythm

Before reporting a change complete:

- `nix flake check` — catches syntax + module-evaluation errors fast.
- `darwin-rebuild build --flake .` — full evaluation, no activation.
- For invasive changes (new module, system-defaults edit, cask
  add/remove): invoke the `test-on-fresh-vm` skill to make sure a
  fresh-mac bootstrap still works.

## Drift anti-patterns (what NOT to do)

- Do NOT add bash logic outside `install.sh` for anything Nix can
  express. Even simple-looking imperative loops grow workarounds.
  (Past evidence: the brew/bun/TS installer that this repo used to be.)
- Do NOT commit a `flake.lock` bump without running `darwin-rebuild
  build --flake .` first. A bad nixpkgs revision rebuilds the world.
- Do NOT delete `$TMPDIR/crrow-dotfiles-install.lock` blindly. Check
  `kill -0 $(cat $TMPDIR/.../pid)` to see if a real installer is
  running; `install.sh` already auto-clears stale locks.
- Do NOT bypass `darwin-rebuild` with a manual `brew install` or
  `defaults write`. Those mutations drift out of the declared state and
  will be undone on the next switch. (`drift-guard.sh` blocks the
  common cases.)
- Do NOT create `AGENTS.md` / `GEMINI.md` / `.cursorrules` /
  `.windsurfrules` as separate files — they are symlinks to `CLAUDE.md`.

## Nix style

Anchors: [nix.dev best practices][nix-bp] for project structure, and
[`nixfmt`][nixfmt] (RFC 166 community standard) for formatting — analog
of `shellcheck` + the Google guide for bash.

The dev toolchain ([`nixfmt-rfc-style`][nixfmt], [`statix`][statix],
[`deadnix`][deadnix]) is **dev-only for this repo** — it lives in
`devShells.<system>.default` in `flake.nix`, not in `home.packages`.
You get it by entering the shell:

```sh
nix develop          # one-shot: drops you in a shell with the tools
# or, if you use direnv:
echo 'use flake' > .envrc && direnv allow   # auto-activates on cd
```

Before reporting a Nix change complete (run inside `nix develop`):

- `nix fmt` — reformat in place (the flake declares
  `formatter.<system> = nixfmt-rfc-style`, so this Just Works).
- `statix check .` — anti-pattern lints (e.g. `lib.mkIf true`,
  redundant `with`).
- `deadnix .` — unused let-bindings, function args, imports.

House rules:

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

[nix-bp]: https://nix.dev/guides/best-practices/
[nixfmt]: https://github.com/NixOS/nixfmt
[statix]: https://github.com/oppiliappan/statix
[deadnix]: https://github.com/astro/deadnix

## Bash style (for the rare cases we touch `install.sh`)

Follow [Google Shell Style Guide][gssg] for the parts that apply on
macOS:

- `#!/usr/bin/env bash` shebang, `set -euo pipefail`, `IFS=$'\n\t'`
- `readonly` for constants, `local` for function variables
- Functions are lowercase_with_underscores, one verb per name
- `[[ ]]` not `[ ]`; always quote `"$var"`
- `printf` not `echo` for anything with interpolation
- Cleanup via `trap … EXIT INT TERM`, never via "and at the end…"
- Every script must pass `shellcheck` clean

[gssg]: https://google.github.io/styleguide/shellguide.html
