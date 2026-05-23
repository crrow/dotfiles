# Justfile for crrow/dotfiles — local VM control for testing the Nix bootstrap.
#
# Spins up a vanilla macOS VM via lume so you can SSH in and try the bootstrap
# end-to-end (or just poke around).
#
# Requires `lume` on PATH:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"

set shell := ["bash", "-cu"]

baseline := "dotfiles-test"
vm       := "dotfiles-run"
image    := "macos-sequoia-vanilla-sparse:latest"

default:
    @just --list

# ─── day-to-day ────────────────────────────────────────────────────────────

# Read-only health check: nix/git/darwin-rebuild present, flake evaluates, VM ready.
doctor:
    @./doctor.sh

# Pull latest main and converge the system to the new declared state.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    git pull --ff-only
    darwin-rebuild switch --flake .

# ─── VM testing ────────────────────────────────────────────────────────────

# Pull the read-only baseline VM image if missing (~22 GB, one-off).
baseline:
    #!/usr/bin/env bash
    set -euo pipefail
    if lume ls | awk 'NR>1{print $1}' | grep -qx '{{baseline}}'; then
      echo "baseline {{baseline}} already present"
    else
      lume pull {{image}} {{baseline}}
    fi

# Mounts host repo at /Volumes/My Shared Files/ (rw); flake.lock writes
# back to the host as uncommitted drift, .user is gitignored.
# Clone baseline → start VM → wait for SSH → prep → launch install.sh.
vm-up: baseline
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -f 'lume run {{vm}}' 2>/dev/null || true
    sleep 1
    lume stop   {{vm}}        >/dev/null 2>&1 || true
    lume delete {{vm}} --force >/dev/null 2>&1 || true
    lume clone  {{baseline}} {{vm}}
    nohup lume run {{vm}} --shared-dir "$(pwd):rw" >/tmp/lume-{{vm}}.log 2>&1 &
    echo "started: pid=$! log=/tmp/lume-{{vm}}.log"
    for i in $(seq 1 60); do
      if lume ssh {{vm}} --timeout 5 -- echo ready 2>/dev/null | grep -q ready; then
        echo "ssh up after ${i} attempts"
        break
      fi
      sleep 5
      [ "$i" -eq 60 ] && { echo "FAIL: VM did not become ssh-able within 5 min" >&2; exit 1; }
    done
    just _vm-prep
    just vm-bootstrap
    echo
    echo "Default creds: lume / lume"
    echo "  just vm-bootstrap  # re-run install.sh without rebuilding the VM"
    echo "  just vm-ssh        # interactive shell"
    echo "  just vm-vnc        # re-open VNC"
    echo "  just vm-down       # stop + delete"

# Internal: install VM-only sudoers + /tmp/run-install.sh wrapper. Remote
# logic lives in scripts/vm-prep.sh, base64-encoded inline so the remote
# pipes its own stdin (lume ssh doesn't reliably forward host stdin, and
# the shared-mount path turned out to be aggressively cached on the
# guest — host edits to vm-prep.sh weren't visible inside the VM).
# HOST_PROXY is passed through as a positional arg.
[private]
_vm-prep:
    #!/usr/bin/env bash
    set -euo pipefail
    proxy="${HOST_PROXY:-http://10.0.0.1:7890}"
    b64=$(base64 < scripts/vm-prep.sh | tr -d '\n')
    lume ssh {{vm}} --timeout 60 -- "echo $b64 | base64 -D | bash -s -- '$proxy'"

# Runs the identical curl|bash command a real-Mac user runs — no VM-
# specific wrapper. Proxy + DOTFILES_DIR come from /etc/zshenv (written
# by _vm-prep). `|| true`: osascript holds the SSH session open until
# Terminal finishes rendering, past lume ssh's timeout — script still starts.
# Auto-called by vm-up; invoke directly to re-run install.sh in a live VM.
#
# Override the branch with DOTFILES_REF, e.g. testing a feature branch:
#   DOTFILES_REF=refactor just vm-bootstrap
# Both the install.sh URL and the env var fed into the bash invocation
# get the same ref, so install.sh's fetch_repo pulls the same tarball.
vm-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    ref="${DOTFILES_REF:-main}"
    url="https://raw.githubusercontent.com/crrow/dotfiles/${ref}/install.sh"
    cmd="DOTFILES_REF=${ref} /bin/bash -c \\\"\$(curl -fsSL ${url})\\\""
    lume ssh {{vm}} --timeout 30 -- \
      "open -a Terminal && sleep 2 && osascript -e 'tell application \"Terminal\" to do script \"${cmd}\"'" \
      || true
    echo "install.sh launched in VM Terminal (ref=${ref}) — watch via VNC; press Enter at the Accessibility prompt."

# Open an interactive SSH session into the running VM (creds: lume / lume).
vm-ssh:
    lume ssh {{vm}}

# Re-open the VNC screen if you closed it.
vm-vnc:
    #!/usr/bin/env bash
    set -euo pipefail
    url=$(lume get {{vm}} -f json 2>/dev/null \
            | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("vncUrl") or "")' 2>/dev/null \
            || true)
    if [ -z "$url" ]; then
      url=$(grep -oE 'vnc://[^ ]+' /tmp/lume-{{vm}}.log 2>/dev/null | tail -1 || true)
    fi
    if [ -z "$url" ]; then
      echo "could not find VNC URL — is the VM running? try: just vm-ls" >&2
      exit 1
    fi
    echo "opening $url"
    open "$url"

# Stop and delete the working VM. Baseline is kept.
vm-down:
    #!/usr/bin/env bash
    lume stop   {{vm}}        >/dev/null 2>&1 || true
    pkill -f 'lume run {{vm}}' 2>/dev/null || true
    sleep 1
    lume delete {{vm}} --force >/dev/null 2>&1 || true
    echo "{{vm}} removed (baseline {{baseline}} kept)"

# List all lume VMs.
vm-ls:
    lume ls

# ─── lint / format ─────────────────────────────────────────────────────────
# Toolchain (shellcheck / shfmt / nixfmt) is pinned in mise.toml. Bootstrap
# on a fresh checkout with `mise install`; mise auto-activates here and puts
# them on PATH. No nix required.

# Write: format all .sh + .nix files in place. Run before committing.
fmt: fmt-sh fmt-nix

# Read-only: fails non-zero on any formatting drift or lint finding. CI/pre-commit.
lint: lint-sh lint-nix
    @echo "lint: ok"

fmt-sh:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(git ls-files '*.sh')
    [ -n "$files" ] || { echo "fmt-sh: no .sh files"; exit 0; }
    shfmt -w -i 2 -ci $files

fmt-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(git ls-files '*.nix')
    [ -n "$files" ] || { echo "fmt-nix: no .nix files"; exit 0; }
    nixfmt $files

lint-sh:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(git ls-files '*.sh')
    [ -n "$files" ] || { echo "lint-sh: no .sh files"; exit 0; }
    shfmt -d -i 2 -ci $files
    shellcheck $files

lint-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(git ls-files '*.nix')
    [ -n "$files" ] || { echo "lint-nix: no .nix files"; exit 0; }
    nixfmt --check $files
