---
name: update-flake
description: |
  Use when the user asks to "update Nix", "bump flake.lock", "upgrade
  packages", "pull latest nixpkgs", or similar. Bumps `flake.lock`,
  builds the system against the new inputs to catch eval/build errors,
  and only switches once the build passes. Aborts cleanly if anything
  is wrong, leaving `flake.lock` either the old version or in a
  buildable new state — never half-applied.

  Do NOT use this for editing the flake itself (adding a new input,
  changing follows). For those, edit `flake.nix` directly — this skill
  only handles the lock-bump rhythm.
---

# Update flake.lock

A `flake.lock` bump can pull in:

- a new nixpkgs revision (rebuilds the world)
- a new nix-darwin or home-manager revision (config schema may change)
- transient breakage from any of the above

The safe rhythm: **update lock → build → eyeball the diff → switch**.
Never `nix flake update && darwin-rebuild switch` in one breath.

## Workflow

### 1. Update the lock

```sh
cd ~/code/personal/dotfiles
nix flake update
```

This bumps every input to the latest revision allowed by its URL spec.
To update a single input only:

```sh
nix flake update nixpkgs        # only nixpkgs
nix flake update home-manager   # only HM
```

### 2. Inspect what changed

```sh
git diff flake.lock | head -50
```

For each bumped input, note the `lastModified` jump. If it's been
months, expect more breakage; if days, lower risk.

### 3. Build (don't switch yet)

```sh
darwin-rebuild build --flake .
```

This evaluates the flake and builds every derivation in the new system
closure. Errors here are cheap — nothing has been activated.

Common failure modes:

- **Module schema change**: home-manager renamed `initExtra` → `initContent`
  in a recent release; build will say "obsolete option". Look up the
  current option name on
  <https://home-manager-options.extranix.com>, edit the module,
  re-build.
- **Package removal**: a package was moved or renamed in nixpkgs. Build
  fails with "attribute not found". Find the new name with
  `nix search nixpkgs <old-name>` or check the nixpkgs PR.
- **Hash mismatch**: someone force-pushed a tarball input. Re-run
  `nix flake update <input>`.

If you can't fix it within ~10 minutes, revert and try later:

```sh
git checkout flake.lock
```

### 4. Optional: VM smoke test

For risky bumps (nixpkgs major jump, home-manager schema change), run
the `test-on-fresh-vm` skill before switching the host. This catches
issues that only appear during fresh activation, not incremental.

### 5. Switch

```sh
darwin-rebuild switch --flake .
```

If activation fails partway, nix-darwin rolls back automatically — the
previous generation is still active. List generations:

```sh
darwin-rebuild --list-generations
```

Roll back manually if needed:

```sh
darwin-rebuild rollback           # back one
# or: /run/current-system/sw/bin/darwin-rebuild switch --switch-generation <n>
```

### 6. Commit

Only after switch succeeds:

```sh
git add flake.lock
git commit -m "chore: bump flake.lock"
```

If a module file changed because of a schema migration, include it in
the same commit and reference the upstream change in the message.

## Don't

- Don't bump and switch without building first. The build step is the
  cheap safety net.
- Don't commit `flake.lock` if the build fails. A broken lock makes the
  repo unbootstrappable for anyone (including a fresh you).
- Don't `nix flake update` inside the install.sh path — install.sh is
  for bootstrap, not maintenance. Updates are a hands-on operation.
