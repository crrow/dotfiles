---
name: test-on-fresh-vm
description: |
  Use this when verifying that this dotfiles repo bootstraps cleanly on a
  brand-new macOS install. Spins up a vanilla macOS VM via lume (Apple
  Virtualization.framework), runs the full bootstrap end-to-end
  (Determinate Nix → clone → `darwin-rebuild switch`), and asserts the
  declared state actually activated.

  Trigger when the user asks to "test on a clean VM", "verify on a fresh
  Mac", "make sure setup works from scratch", or before tagging a new
  release. Also use after any change to `flake.nix`, `modules/*.nix`,
  `install.sh`, or the bootstrap instructions in `README.md`.

  Do NOT use for `nix flake check` / local builds — those are faster
  on the host.
---

# Test dotfiles bootstrap on a fresh macOS VM

You drive this directly via the Bash tool. Phases below: each is a few
commands, you read the output, decide the next step. Most of the value
is in the **gotchas** section.

## Prereqs (one-time)

```bash
# 1. Install lume (CLI to ~/.local/bin, daemon as LaunchAgent on :7777)
command -v lume >/dev/null \
  || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"

# 2. Pull the vanilla macOS baseline (~22 GB sparse). Treat as read-only.
lume ls | awk 'NR>1{print $1}' | grep -qx 'dotfiles-test' \
  || lume pull macos-sequoia-vanilla-sparse:latest dotfiles-test
```

If `lume ls` shows other people's VMs already running, **stop and warn
the user** — Apple's VZ framework hard-caps at **2 simultaneous VMs**.

## Workflow

Clone baseline → start → ssh → bootstrap → verify → delete clone.
Or just use the Justfile shortcuts (`just vm-up` / `just vm-down`).

### 1. Reset + start the working VM

```bash
just vm-down >/dev/null 2>&1 || true   # idempotent: noop if already gone
just vm-up                              # clone, start, wait for ssh
```

### 2. Run the bootstrap inside the VM

The README's one-liner, with the lume-VM-only proxy bit prepended (lume
NAT can't resolve github.com; the host proxy at `10.0.0.1:7890` is
reachable from the VM through the NAT gateway).

Drop the script onto the VM via base64 + tmpfile. **Do not pass
multi-line scripts directly to `lume ssh`** — it tokenizes oddly and
breaks at newlines. **Do not wrap with `script -q`** — it makes bash
interactive and echoes every line.

```bash
# All three are externally configurable. Defaults match the lume image.
HOST_PROXY="${HOST_PROXY:-http://10.0.0.1:7890}"
VM_USER="${VM_USER:-lume}"
VM_PASSWORD="${VM_PASSWORD:-lume}"     # lume's bake-in default; change at your fork

cat > /tmp/dotfiles-bootstrap.sh <<EOF
#!/bin/bash
set -euo pipefail

echo "==> enable passwordless sudo for ${VM_USER}"
echo '${VM_PASSWORD}' | sudo -S -v   # prime the timestamp cache once
sudo tee /etc/sudoers.d/dotfiles-test >/dev/null <<'SUDOERS'
${VM_USER} ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
SUDOERS
sudo chmod 440 /etc/sudoers.d/dotfiles-test

echo "==> route through host proxy ${HOST_PROXY}"
export HTTP_PROXY="${HOST_PROXY}"  HTTPS_PROXY="${HOST_PROXY}"
export http_proxy="${HOST_PROXY}"  https_proxy="${HOST_PROXY}"
export ALL_PROXY="${HOST_PROXY}"   all_proxy="${HOST_PROXY}"

echo "==> run the dotfiles installer"
/bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/crrow/dotfiles/main/install.sh)"

echo "==> DONE"
EOF

B64=$(base64 < /tmp/dotfiles-bootstrap.sh | tr -d '\n')
REMOTE='tmpfile=$(mktemp); echo '"$B64"' | base64 -d > "$tmpfile"; bash "$tmpfile" 2>&1; rc=$?; rm -f "$tmpfile"; exit $rc'

lume ssh dotfiles-run --timeout 3600 -- "$REMOTE" 2>&1 | tee /tmp/bootstrap.log
```

**Output is buffered** in 4-8 KB chunks since stdout isn't a TTY — long
steps look hung from outside. macOS has no `stdbuf`; live streaming
would need real PTY plumbing. Accept it; sanity-check with side-channel
`lume ssh dotfiles-run -- 'ps -ax | grep nix'` if you need to verify a
long step is still alive. Determinate Nix install + `darwin-rebuild
switch` together typically take 10-25 min.

### 3. Verify

```bash
lume ssh dotfiles-run --timeout 30 -- bash -lc '
  set -e
  # Nix itself is present
  command -v nix
  # Determinate daemon is loaded
  launchctl list | grep -q org.nixos.nix-daemon && echo OK nix-daemon
  # nix-darwin generation is active
  test -d /run/current-system && echo OK current-system
  # Home Manager profile is active for the user
  test -L $HOME/.nix-profile && echo OK home-manager
  # Key tools landed (from modules/home.nix packages)
  command -v starship
  command -v zellij
  command -v mise
  command -v rg
  # Ghostty cask installed by nix-darwin homebrew bridge
  test -d /Applications/Ghostty.app && echo OK ghostty
  echo PASS
'
```

### 4. Teardown

```bash
just vm-down
```

Don't delete the baseline `dotfiles-test` — re-pulling is a 22 GB
download.

## Gotchas (every one of these cost real time)

- **Apple VZ caps at 2 active VMs.** `lume run` errors with "The number
  of virtual machines exceeds the limit" when a previous run left a
  zombie. `lume ls` may report `stopped` while the underlying
  `lume run` host process is still alive. Kill it:
  `pkill -f 'lume run <name>'`. `just vm-up` does this defensively.

- **lume NAT DNS returns SERVFAIL for github.com.** mise.run resolves
  (Cloudflare) but raw.githubusercontent.com and github.com don't.
  Setting public DNS works for resolution but git's HTTP/2 still stalls
  inside lume's NAT. **Use the host's HTTP proxy** (`10.0.0.1:7890` if
  yours is set up) — reachable from the VM via the NAT gateway. Pass
  via `HOST_PROXY` env when invoking this skill.

- **`sudo -S` and heredocs fight over stdin.** `echo pwd | sudo -S
  tee … <<EOF` makes sudo read the heredoc body as the password.
  Split it: `echo lume | sudo -S -v` first (primes the timestamp
  cache), then heredoc-fed `sudo tee` runs without prompting.

- **`lume ssh -- bash -lc "<multi-line>"` mis-tokenizes.** Wrap the
  script in base64 and decode into a tmpfile remotely.

- **`script -q /dev/null bash` makes bash interactive** under the pty —
  each input line gets echoed back like a typing demo. Don't.

- **`lume ssh` default timeout is 60 s.** Determinate Nix install +
  `darwin-rebuild switch` takes 10-25 min; use `--timeout 3600`. If
  the SSH session times out near the tail end, Nix has usually already
  finished — verify state, don't blindly restart.

- **`lume ssh` output is buffered** because remote stdout is a pipe,
  not a TTY. Accept buffered chunks; check progress with side-channel
  `lume ssh ... -- 'ps ...'` queries.

- **Default VM credentials are `lume`/`lume`.** `lume ssh` handles the
  password automatically.

- **Determinate Nix installer needs the controlling tty** for its sudo
  prompt — but our base64+tmpfile pattern keeps stdin attached so this
  works. With passwordless sudo configured (step above), the installer
  proceeds without prompting at all.

## When this isn't enough

- **Driving GUI apps** (verify Ghostty actually launches, dock settings
  rendered correctly): use VNC (`just vm-vnc`) and eyeball it. The
  installer's job is declarative-config-applied; GUI behavior is a
  visual check.
- **Real M-series with your own user account**: that's the README's
  path — this skill is the *fresh-machine* surrogate.
