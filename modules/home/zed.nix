{ ... }:

# Declarative Zed config. The app itself comes from the `zed` Homebrew
# cask (see modules/darwin/homebrew.nix) — like ghostty, it's a signed
# macOS GUI app we don't want Nix to build — so `package = null` keeps
# Home Manager to writing the config files only.
#
# mutableUserSettings/Keymaps stay at their default (true): on switch
# the declared values are merged into ~/.config/zed/{settings,keymap}.json,
# but the files stay writable so Zed-UI tweaks still work. Source mirrors
# the host's existing config on the day this module was written.
#
# Note: `theme` / `icon_theme` below reference Zed *extensions* installed
# separately (Catppuccin Blur is a local dev extension, not published), so
# they aren't declared here — install them once from the Zed extensions UI.

{
  programs.zed-editor = {
    enable  = true;
    package = null;

    userSettings = {
      project_panel.dock = "left";
      outline_panel.dock = "left";
      collaboration_panel.dock = "left";
      git_panel.dock = "left";

      icon_theme = "Material Icon Theme";
      theme = "Catppuccin Frappé (Blur)";

      show_signature_help_after_edits = true;
      features.edit_prediction_provider = "zed";

      agent = {
        dock = "right";
        default_model = {
          provider = "zed.dev";
          model = "claude-sonnet-4";
        };
      };

      autosave = "on_focus_change";
      base_keymap = "VSCode";

      buffer_font_size = 16;
      # buffer_font_family = "Comic Mono";
      buffer_font_family = "Google Sans Code";
      ui_font_size = 16;

      cursor_blink = true;
      cursor_shape = "block";
      current_line_highlight = "gutter";

      enable_language_server = true;
      formatter = "language_server";
      format_on_save = "on";
      tab_size = 4;
      vim_mode = false;

      git.inline_blame.enabled = true;
      journal.hour_format = "hour24";
      tabs.git_status = true;

      inlay_hints = {
        enabled = true;
        show_type_hints = true;
        show_parameter_hints = true;
        show_other_hints = true;
      };

      languages = {
        Rust.preferred_line_length = 60;
        # Formatting with ZLS matches `zig fmt` (see Zig FAQ).
        Zig = {
          formatter = "language_server";
          format_on_save = "on";
          # Keep zls as the primary language server.
          language_servers = [ "zls" "..." ];
          code_actions_on_format = {
            "source.fixAll" = true;
            "source.organizeImports" = true;
          };
        };
        JSON.tab_size = 4;
        YAML.tab_size = 4;
      };

      lsp = {
        gopls.initialization_options.hints = {
          assignVariableTypes = true;
          compositeLiteralFields = true;
          compositeLiteralTypes = true;
          constantValues = true;
          functionTypeParameters = true;
          parameterNames = true;
          rangeVariableTypes = true;
        };

        rust-analyzer.initialization_options = {
          cargo = {
            allFeatures = true;
            buildScripts = {
              enable = true;
              rebuildOnSave = true;
            };
          };
          check = {
            allTargets = false;
            command = "check";
          };
          checkOnSave = true;
          hover.references.enabled = true;
          imports = {
            granularity.group = "crate";
            prefix = "self";
            merge.glob = true;
          };
          inlayHints = {
            maxLength = null;
            lifetimeElisionHints = {
              useParameterNames = true;
              enable = "skip_trivial";
            };
            closureReturnTypeHints.enable = "always";
          };
          procMacro.enable = true;
        };

        # Absolute paths because zls/zig come from Homebrew, not PATH.
        zls.binary.path = "/opt/homebrew/bin/zls";
        zls.settings.zig_exe_path = "/opt/homebrew/bin/zig";

        taplo.settings.array_auto_collapse = false;
      };

      terminal = {
        font_family = "JetBrainsMonoNL Nerd Font";
        blinking = "on";
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };
    };

    userKeymaps = [
      {
        context = "Editor";
        bindings = {
          "ctrl-shift-g" = "editor::Rename";
          "ctrl-shift-h" = "editor::GoToDefinition";
          "cmd-alt-n" = "editor::Rename";
        };
      }
      {
        context = "Workspace";
        bindings."ctrl--" = "workspace::ToggleBottomDock";
      }
    ];
  };
}
