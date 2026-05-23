{ lib, ... }:

# yabai (tiling) + skhd (hotkeys) + optional sketchybar config. The
# binaries come from Homebrew (declared in modules/darwin/homebrew.nix);
# this module owns the user-level configs AND the post-switch
# activation logic (sketchybar helpers, SbarLua, service start).
#
# First-time setup the user must STILL do manually — only Accessibility
# consent can't be automated:
#   System Settings → Privacy & Security → Accessibility:
#     enable yabai and skhd
# install.sh prompts and opens that pane during bootstrap.

{
  ###
  ### yabai — config symlinked from ./yabai/yabairc
  ###
  home.file.".config/yabai/yabairc" = {
    source     = ../../yabai/yabairc;
    executable = true;
  };

  ###
  ### skhd — config symlinked from ./skhd/skhdrc
  ###
  home.file.".config/skhd/skhdrc".source = ../../skhd/skhdrc;

  ###
  ### sketchybar — whole tree symlinked from ./sketchybar/
  ### Helpers' compiled binaries are NOT in the repo; rebuilt by the
  ### activation hook below.
  ###
  home.file.".config/sketchybar" = {
    source    = ../../sketchybar;
    recursive = true;
  };

  ###
  ### Post-symlink activation: compile sketchybar's C event-provider
  ### binaries, install SbarLua + lunajson, and start yabai/skhd
  ### launchd agents. Runs on every `darwin-rebuild switch`. Idempotent
  ### — `make` no-ops when outputs are fresh, `--start-service` is safe
  ### to re-invoke, SbarLua build is guarded on the output file.
  ###
  # `writeBoundary` is the canonical anchor: by the time it runs, all
  # `home.file` symlinks (sketchybar config, etc) are in place.
  home.activation.windowManagerPostInstall =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # PATH at activation is HM-minimal; brew lives in /opt/homebrew
      # (Apple Silicon) or /usr/local. Both prepended unconditionally —
      # missing dir = silent no-op.
      export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

      # (a) Compile sketchybar's bundled C helpers — Makefile under each
      # event_providers/* subdir. Skip the whole step if sketchybar isn't
      # actually installed (vm-tests on macOS without yabai brew etc).
      helpers="$HOME/.config/sketchybar/helpers/event_providers"
      if [ -d "$helpers" ] && command -v make >/dev/null 2>&1; then
        for d in "$helpers"/*/; do
          [ -f "$d/makefile" ] || [ -f "$d/Makefile" ] || continue
          ( cd "$d" && $DRY_RUN_CMD make >/dev/null 2>&1 ) || \
            echo "  ! sketchybar helper build failed in $d (non-fatal)"
        done
      fi

      # (b) SbarLua — Lua bindings sketchybar's config requires (loaded
      # via helpers/init.lua). Not on luarocks/nixpkgs; build from
      # upstream. Guard on the output so re-runs are free.
      sbarlua="$HOME/.local/share/sketchybar_lua/sketchybar.so"
      if [ -f "$HOME/.config/sketchybar/sketchybarrc" ] \
         && [ ! -f "$sbarlua" ] \
         && command -v lua >/dev/null 2>&1 \
         && command -v luarocks >/dev/null 2>&1 \
         && command -v git >/dev/null 2>&1; then
        tmp=$(mktemp -d -t sbarlua)
        if ( cd "$tmp" \
             && $DRY_RUN_CMD git clone --depth 1 https://github.com/FelixKratz/SbarLua.git \
             && cd SbarLua && $DRY_RUN_CMD make install ) >/dev/null 2>&1; then
          echo "  ✓ SbarLua installed to $sbarlua"
        else
          echo "  ! SbarLua build failed (sketchybar will render empty)"
        fi
        $DRY_RUN_CMD rm -rf "$tmp"

        # Companion: lunajson (pure-Lua dep referenced by some bar items).
        if ! luarocks --lua-version 5.5 list 2>/dev/null | grep -q lunajson; then
          $DRY_RUN_CMD luarocks --lua-version 5.5 install lunajson >/dev/null 2>&1 \
            || echo "  ! lunajson install failed"
        fi
      fi

      # (c) Start launchd agents. The asmvik yabai/skhd fork doesn't ship
      # service plists, so use each tool's built-in `--start-service`
      # (writes ~/Library/LaunchAgents/*.plist and loads it). sketchybar
      # intentionally NOT started here — fresh VMs keep the native menu
      # bar until the user opts in.
      for svc in yabai skhd; do
        command -v "$svc" >/dev/null 2>&1 || continue
        $DRY_RUN_CMD "$svc" --start-service >/dev/null 2>&1 || true
      done
    '';
}
