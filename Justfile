# Justfile for crrow/dotfiles — manual VM control.
# Spins up a vanilla macOS VM via lume so you can SSH in and try the bootstrap
# by hand (helpful for iterating on `src/setup.ts` or `home/**`).
#
# Run `just` to list targets.

set shell := ["bash", "-cu"]

baseline := "dotfiles-test"
vm       := "dotfiles-run"
image    := "macos-sequoia-vanilla-sparse:latest"

default:
    @just --list

# Ensure the read-only baseline VM exists. Pulls ~22 GB if missing (one-off).
baseline:
    #!/usr/bin/env bash
    set -euo pipefail
    if lume ls | awk '{print $1}' | grep -qx '{{baseline}}'; then
      echo "baseline {{baseline}} already present"
    else
      lume pull {{image}} {{baseline}}
    fi

# Clone the baseline into a fresh working VM and wait until SSH is up.
vm-up: baseline
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -f 'lume run {{vm}}' 2>/dev/null || true
    sleep 1
    lume stop {{vm}} >/dev/null 2>&1 || true
    lume delete {{vm}} --force >/dev/null 2>&1 || true
    lume clone {{baseline}} {{vm}}
    nohup lume run {{vm}} --no-display >/tmp/lume-{{vm}}.log 2>&1 &
    echo "started: pid=$! log=/tmp/lume-{{vm}}.log"
    for i in $(seq 1 60); do
      if lume ssh {{vm}} --timeout 5 -- echo ready 2>/dev/null | grep -q ready; then
        echo "ssh up after ${i} attempts"
        echo
        echo "VM ready. Default creds: lume / lume"
        echo "  just vm-ssh    # open an interactive shell inside"
        echo "  just vm-down   # stop + delete"
        exit 0
      fi
      sleep 5
    done
    echo "FAIL: VM did not become ssh-able within 5 min" >&2
    exit 1

# Open an interactive SSH session into the running VM.
vm-ssh:
    lume ssh {{vm}}

# Stop and delete the working VM. Baseline is kept.
vm-down:
    #!/usr/bin/env bash
    lume stop {{vm}} >/dev/null 2>&1 || true
    pkill -f 'lume run {{vm}}' 2>/dev/null || true
    sleep 1
    lume delete {{vm}} --force >/dev/null 2>&1 || true
    echo "{{vm}} removed (baseline {{baseline}} kept)"

# List all lume VMs.
vm-ls:
    lume ls
