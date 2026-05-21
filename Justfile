# Justfile for crrow/dotfiles — manual VM control.
# Spins up a vanilla macOS VM via lume so you can SSH in and try the
# bootstrap by hand. All non-trivial logic lives in scripts/*.ts —
# the recipes here are thin shims.
#
# Run `just` to list targets.

set shell := ["bash", "-cu"]

default:
    @just --list

# Pull the read-only baseline VM image if missing (~22 GB, one-off).
baseline:
    bun run scripts/vm-baseline.ts

# Clone baseline → start a working VM → wait for SSH. VNC opens automatically.
vm-up:
    bun run scripts/vm-up.ts

# Open an interactive SSH session into the running VM (creds: lume / lume).
vm-ssh:
    lume ssh dotfiles-run

# Re-open the VNC screen if you closed it.
vm-vnc:
    bun run scripts/vm-vnc.ts

# Stop and delete the working VM (baseline kept).
vm-down:
    bun run scripts/vm-down.ts

# List all lume VMs.
vm-ls:
    lume ls
