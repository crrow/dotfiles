---
name: test-on-fresh-vm
description: |
  Use this when verifying that this dotfiles repo bootstraps cleanly on a
  brand-new macOS install. Spins up a vanilla macOS VM via lume (Apple
  Virtualization.framework), runs the full bootstrap end-to-end (Homebrew
  + Xcode CLT + mise + bun + the TS installer + symlinks), and asserts
  that the resulting state is what the README promises.

  Trigger when the user asks to "test on a clean VM", "verify on a fresh
  Mac", "make sure setup works from scratch", or before tagging a new
  release. Also use after any change to `src/setup.ts`, `home/`, or the
  bootstrap instructions in `README.md`.

  Do NOT use for unit tests, typecheck, or anything that doesn't need a
  full OS — those are faster locally.
---

# Test dotfiles bootstrap on a fresh macOS VM

You drive this directly via the Bash tool — there's no harness script in
the repo. Each phase below is a small handful of commands you run, read
the output, and decide the next step. Most of the value is in the
**gotchas** section — they were all hit during the first end-to-end run
and each one cost real time.

## Prereqs (one-time)

```bash
# 1. Install lume (puts CLI in ~/.local/bin, daemon as LaunchAgent on :7777)
command -v lume >/dev/null \
  || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"

# 2. Pull the vanilla macOS baseline (~22 GB, sparse on disk).
#    Name it `dotfiles-test` — we treat it as a read-only golden image
#    and clone from it for every test run.
lume ls | grep -q '^dotfiles-test ' \
  || lume pull macos-sequoia-vanilla-sparse:latest dotfiles-test
```

If `lume ls` shows other people's VMs already running, **stop here and
warn the user** — Apple's VZ framework hard-caps at **2 simultaneous
VMs**, and starting a third silently fails.

## Workflow

The pattern is: **clone baseline → start → ssh → bootstrap → verify →
delete clone**. Each test run starts from a true fresh OS image.

### 1. Reset the working VM

```bash
# Idempotent: stop + delete any leftover from a prior run, then clone.
pkill -f 'lume run dotfiles-run' 2>/dev/null; sleep 1
lume stop dotfiles-run 2>/dev/null
lume delete dotfiles-run --force 2>/dev/null
lume clone dotfiles-test dotfiles-run
```

### 2. Start the VM and wait for SSH

`lume run` is foreground/blocking — background it, then poll.

```bash
nohup lume run dotfiles-run --no-display >/tmp/lume-run.log 2>&1 &
echo "lume run pid=$!"

# Poll until SSH is ready. Default creds are lume/lume (handled by `lume ssh`).
for i in $(seq 1 60); do
  if lume ssh dotfiles-run --timeout 5 -- echo ready 2>/dev/null | grep -q ready; then
    echo "ssh up after ${i} attempts"
    break
  fi
  sleep 5
done
```

### 3. Run the bootstrap inside the VM

Drop the script onto the VM via base64 + tmpfile. **Do not try to pass
multi-line scripts directly to `lume ssh` — it tokenizes oddly and
breaks at newlines.** Do not wrap with `script -q` either — it puts
bash in interactive mode and each line gets echoed back as if typed.

The bootstrap script itself (paste exactly):

```bash
BRANCH="${BRANCH:-main}"
REPO="${REPO:-https://github.com/crrow/dotfiles.git}"
HOST_PROXY="${HOST_PROXY:-${HTTP_PROXY:-${http_proxy:-}}}"

read -r -d '' SCRIPT <<EOF || true
set -euo pipefail

echo "==> enable passwordless sudo for lume + env_keep proxy"
echo lume | sudo -S -v                                # prime sudo cache once
sudo tee /etc/sudoers.d/lume-test >/dev/null <<'SUDOERS'
lume ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
SUDOERS
sudo chmod 440 /etc/sudoers.d/lume-test

$( [ -n "$HOST_PROXY" ] && cat <<PROXY
echo "==> route VM through host proxy $HOST_PROXY"
export HTTP_PROXY="$HOST_PROXY"   HTTPS_PROXY="$HOST_PROXY"
export http_proxy="$HOST_PROXY"   https_proxy="$HOST_PROXY"
export ALL_PROXY="$HOST_PROXY"    all_proxy="$HOST_PROXY"
cat > "\$HOME/.gitconfig" <<GIT
[http]
	proxy = $HOST_PROXY
[https]
	proxy = $HOST_PROXY
GIT
PROXY
)

echo "==> install Homebrew (installs Xcode CLT)"
if ! command -v brew >/dev/null; then
  NONINTERACTIVE=1 /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if   [ -x /opt/homebrew/bin/brew ]; then eval "\$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ];    then eval "\$(/usr/local/bin/brew shellenv)"
fi

echo "==> brew install mise git"
brew install mise git

echo "==> clone dotfiles ($BRANCH)"
rm -rf "\$HOME/dotfiles"
git clone -b $BRANCH $REPO "\$HOME/dotfiles"
cd "\$HOME/dotfiles"

echo "==> mise install (bun)"
mise trust
mise install
eval "\$(mise activate bash)"

echo "==> bun install"
bun install

echo "==> bun run setup"
bun run setup
EOF

B64=$(printf '%s' "$SCRIPT" | base64)
REMOTE='tmpfile=$(mktemp); echo '"$B64"' | base64 -d > "$tmpfile"; bash "$tmpfile" 2>&1; rc=$?; rm -f "$tmpfile"; exit $rc'

lume ssh dotfiles-run --timeout 3600 -- "$REMOTE"
```

When `lume ssh` exits 0, the bootstrap finished. **Output is buffered**
in 4-8 KB chunks since stdout isn't a TTY; long steps look hung from
the outside. That's cosmetic — let it run.

### 4. Verify

Each of these must succeed. The first failure is the bug.

```bash
lume ssh dotfiles-run --timeout 30 -- bash -lc '
  set -e
  test -L $HOME/.zshrc                                       # zshrc symlinked
  readlink $HOME/.zshrc | grep -q dotfiles/home/.zshrc       # to our repo
  test -L $HOME/.config/ghostty/config                       # ghostty
  test -L $HOME/.config/starship.toml                        # starship
  test -L $HOME/.config/zellij/config.kdl                    # zellij
  command -v starship
  command -v zellij
  command -v mise
  command -v bun
  test -d $HOME/.oh-my-zsh
  test -d $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
  echo PASS
'
```

### 5. Teardown

```bash
lume stop dotfiles-run 2>/dev/null
pkill -f 'lume run dotfiles-run' 2>/dev/null; sleep 1
lume delete dotfiles-run --force 2>/dev/null
```

**Don't delete the baseline `dotfiles-test`** — re-pulling it is a 22 GB
download.

## Gotchas (every one of these cost real time)

- **Vanilla = truly vanilla.** No Xcode CLT, no brew, no git, no mise.
  `git` exists as a stub at `/usr/bin/git` that pops a GUI dialog when
  you actually call it. Letting Homebrew's installer run first solves
  this — it installs CLT non-interactively as long as sudo is set up.

- **Apple VZ caps at 2 active VMs.** If `lume run` errors with "The
  number of virtual machines exceeds the limit", a previous run left
  a zombie. `lume ls` may report the VM as `stopped` while the underlying
  `lume run` process and its `Virtualization.VirtualMachine` XPC service
  are still alive. Kill them: `pkill -f 'lume run <name>'`.

- **lume NAT DNS returns SERVFAIL for github.com.** mise.run resolves
  (Cloudflare) but raw.githubusercontent.com and github.com don't.
  Setting `networksetup -setdnsservers ... 1.1.1.1 8.8.8.8` works for
  DNS but git's HTTP/2 still stalls in NAT. **Use the host's proxy**
  (`10.0.0.1:7890` if available — reachable from the VM via the NAT
  gateway). Pass via `HOST_PROXY` env when invoking this skill.

- **`sudo -S` and heredocs fight over stdin.** `echo pwd | sudo -S
  tee … <<EOF` makes sudo read the heredoc body as the password. Split
  it: `echo lume | sudo -S -v` first (primes the timestamp cache),
  then heredoc-fed `sudo tee` runs without a password prompt.

- **`lume ssh -- bash -lc "<multi-line>"` mis-tokenizes.** Wrap the
  script in base64 and decode into a tmpfile remotely (see step 3).

- **`script -q /dev/null bash` makes bash interactive** under the pty —
  each input line gets echoed back like a typing demo. Don't.

- **`lume ssh` default timeout is 60 s.** Bootstrap takes 5-15 min.
  Use `--timeout 3600`.

- **`lume ssh` output is buffered** because remote stdout is a pipe,
  not a TTY. macOS has no `stdbuf`; live streaming would need real PTY
  plumbing. Accept buffered chunks; check progress with a side-channel
  `lume ssh ... -- 'ps -ax | grep brew'` if you need to verify a long
  step is still alive.

- **Default VM credentials are `lume`/`lume`.** `lume ssh` handles the
  password automatically.

## When this isn't enough

- **Driving GUI apps** (verify Ghostty actually launches) — needs cua
  Python SDK or VNC. Out of scope here.
- **Testing against a real M-series with my own user account** — that's
  the README's path; this skill explicitly tests the *fresh-machine*
  path.
