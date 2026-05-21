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

# Pull the read-only baseline VM image if missing (~22 GB, one-off).
baseline:
    #!/usr/bin/env bash
    set -euo pipefail
    if lume ls | awk 'NR>1{print $1}' | grep -qx '{{baseline}}'; then
      echo "baseline {{baseline}} already present"
    else
      lume pull {{image}} {{baseline}}
    fi

# Clone baseline → start a working VM → wait for SSH. VNC opens automatically.
vm-up: baseline
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -f 'lume run {{vm}}' 2>/dev/null || true
    sleep 1
    lume stop   {{vm}}        >/dev/null 2>&1 || true
    lume delete {{vm}} --force >/dev/null 2>&1 || true
    lume clone  {{baseline}} {{vm}}
    nohup lume run {{vm}} >/tmp/lume-{{vm}}.log 2>&1 &
    echo "started: pid=$! log=/tmp/lume-{{vm}}.log"
    for i in $(seq 1 60); do
      if lume ssh {{vm}} --timeout 5 -- echo ready 2>/dev/null | grep -q ready; then
        echo "ssh up after ${i} attempts"
        echo
        echo "VM ready. Default creds: lume / lume"
        echo "  just vm-ssh    # interactive shell"
        echo "  just vm-vnc    # re-open VNC"
        echo "  just vm-down   # stop + delete"
        exit 0
      fi
      sleep 5
    done
    echo "FAIL: VM did not become ssh-able within 5 min" >&2
    exit 1

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
