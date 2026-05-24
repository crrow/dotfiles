# dotfiles

Personal macOS environment as a [Nix flake](https://nixos.wiki/wiki/Flakes).
[nix-darwin](https://github.com/LnL7/nix-darwin) declares system-level state
(macOS defaults, Homebrew casks); [Home Manager](https://github.com/nix-community/home-manager)
declares the user-level stuff (CLI tools, zsh, prompt, dotfiles).

Idempotent by construction — every run converges the system toward the
declared state. Re-running `darwin-rebuild switch` is always safe.

## What's inside

- **Hosts** (`hosts/<hostname>/default.nix`): per-machine entry; the
  flake auto-discovers every subdirectory and exposes it as
  `darwinConfigurations.<hostname>`
- **System** (`modules/darwin/`): nix daemon + macOS defaults
  (Dock, Finder, key repeat, …) → `system.nix`; Homebrew bridge for
  casks (Ghostty) and brews → `homebrew.nix`
- **User** (`modules/home/`): zsh + oh-my-zsh + powerlevel10k,
  [zellij](https://zellij.dev), [mise](https://mise.jdx.dev), git (with delta),
  fzf, bat, eza, fd, ripgrep — one file per concern
- **Terminal**: [Ghostty](https://ghostty.org) (cask) with config in
  `modules/home/ghostty.nix`

## Bootstrap on a new macOS

One line, from a fresh user shell:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"
```

What `install.sh` does (intentionally minimal — ~100 lines):

1. Persists `$HTTPS_PROXY` (if set) to `~/.config/dotfiles/proxy.env` —
   the single source of truth every Nix module reads from.
2. Installs [Determinate Nix](https://determinate.systems/nix) if `nix`
   isn't already on PATH.
3. Fetches the repo to `~/code/personal/dotfiles` (tarball — no git
   dependency yet).
4. Hands off: `sudo nix run nix-darwin#darwin-rebuild -- switch --flake path:…`

Everything else is declarative under `modules/darwin/`:

- `proxy.nix` — writes `/etc/{sudoers.d/dotfiles-proxy,gitconfig,curlrc,zshenv.local}` from `proxy.env`
- `xcode-clt.nix` — installs Command Line Tools non-interactively via `softwareupdate`
- `nix-daemon-proxy.nix` — injects proxy into Determinate's launchd plist + restarts the daemon
- `homebrew.nix` — declarative brew taps/brews/casks via `nix-homebrew`
- `system.nix` — macOS defaults, primary user, nix daemon

Open a new shell when it's done.

One manual step the OS won't let any installer automate:
**grant yabai + skhd Accessibility consent**
(System Settings → Privacy & Security → Accessibility — TCC is SIP-protected).
Then run `just postinstall` to restart the services.

Env knobs: `DOTFILES_DIR` (default `~/code/personal/dotfiles`),
`DOTFILES_REF` (default `main`).

## Day-to-day

```sh
cd ~/code/personal/dotfiles
just doctor                            # verify host is healthy (read-only)
$EDITOR modules/home.nix               # change something
darwin-rebuild switch --flake .        # apply

just update                            # git pull + switch
nix flake update                       # bump pinned inputs
darwin-rebuild switch --flake .
```

`darwin-rebuild switch` will roll back automatically if activation fails —
nothing partial gets left on disk.

## Layout

```
.
├── install.sh           # bash bootstrap: Determinate Nix → clone → switch
├── doctor.sh            # read-only health check (or: just doctor)
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
