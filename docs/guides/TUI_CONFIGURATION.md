# Barista TUI Configuration Guide

The `barista` command provides a terminal-based user interface (TUI) for
configuring your SketchyBar status bar. No compilation is required; it works on
machines with Python 3.9 or newer.

## Quick Start

```bash
# From the barista repository
cd ~/src/lab/barista
./bin/barista

# Or if barista/bin is in your PATH
barista

# Open an explicit state file instead of the default
./bin/barista --config /path/to/state.json
```

`--config` is an explicit load-and-save boundary: the TUI reads and writes that
state file instead of `~/.config/sketchybar/state.json`. Without the flag,
`BARISTA_CONFIG_DIR` still selects the configuration directory.
`Ctrl+R` reloads only when the selected file is named `state.json`, because the
SketchyBar runtime always reads that basename. Other explicit filenames remain
safe save-only editing targets.

## CLI Fallbacks (No GUI Build)

If you can’t build the native GUI on a machine, you can still update `state.json` using the TUI or the CLI scripts.

### TUI (preferred)

```bash
bin/open_control_panel.sh --tui
# Or persist the work-machine fallback path:
./scripts/setup_machine.sh --yes --panel-mode tui --runtime-backend lua
```

### CLI scripts (Python/Lua)

`scripts/runtime_update.sh` uses Python when available and falls back to Lua.

```bash
./scripts/runtime_update.sh bar-color "0xC021162F" 45
./scripts/runtime_update.sh widget-toggle battery off

# Lua directly (if you prefer)
lua ./scripts/runtime_update.lua bar-height 32
```

### Manual edit

Open `~/.config/sketchybar/state.json` in any editor and reload:

```bash
./plugins/reload_sketchybar.sh
```

## Requirements

- Python 3.9+
- textual (TUI framework)
- pydantic (config validation)

Install dependencies:
```bash
python3 -m pip install -r config/requirements.txt
# Or: python3 -m pip install textual pydantic pyyaml
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Save configuration |
| `Ctrl+R` | Save & reload SketchyBar |
| `Ctrl+Q` | Quit |
| `Escape` | Quit |
| `Tab` | Next field |
| `Shift+Tab` | Previous field |

## Tabs

### General

Configure the status bar's appearance:

- **Bar Height** (20-50): Height of the status bar in pixels
- **Corner Radius** (0-16): Rounded corners for bar elements
- **Blur Radius** (0-80): Background blur effect
- **Widget Scale** (0.85-1.25): Scale factor for widgets
- **Bar Color**: ARGB hex color (e.g., `0xC021162F`)
- **Theme**: Select from available themes (default, espresso, mocha, etc.)

### Widgets

Enable or disable status bar widgets:

- **Clock**: Time display with calendar popup
- **Battery**: Battery status indicator
- **Volume**: Volume control
- **Network**: Network status
- **System Info**: CPU, memory, disk usage popup

The System Info controls match the active runtime rows:

- **CPU**: CPU usage and load
- **Memory**: used and total memory
- **Disk**: Data-volume usage
- **Network**: active interface and address
- **Swap**: swap usage
- **Uptime**: system uptime
- **Top CPU**: highest-CPU process
- **Popup Actions**: Activity Monitor and System Settings launch behavior

The seven metric toggles control row visibility independently. Disabling Popup
Actions keeps enabled metrics visible, leaves Top CPU informational, and removes
the Activity Monitor and System Settings launchers. The legacy
`system_info_items.docs` key remains preserved for compatibility but is
intentionally hidden because it no longer creates popup rows.

### Spaces

Configure macOS Spaces/desktops:

- **Icons**: Set custom icons for each space (supports Nerd Font glyphs)
- **Layout Mode**: float, bsp, or stack (requires Yabai)

### Icons

Customize icons used throughout the status bar. Paste Nerd Font glyphs from [nerdfonts.com](https://www.nerdfonts.com/cheat-sheet).

### Integrations

Toggle integrations with external tools:

- **Yaze**: ROM hacking editor
- **Emacs**: Org-mode integration
- **Halext**: Task management

Also configure custom paths for your machine.

### Advanced

- **Font Settings**: Configure icon, text, and number fonts
- **Work Apps Data**: Configure the Google Workspace domain and the
  machine-local apps data file
- **Feature Toggles**: Enable/disable Yabai shortcuts
- **Raw JSON**: Read-only preview of the configuration the TUI loaded

When Work Apps Data changes, Barista updates only rows whose IDs begin with
`work_google_`. Other rows in the active apps file (or the state fallback when
the file is empty) are retained, and the derived file is rolled back if the
state save fails. Legacy `work_google_` duplicates are removed from
`menus.apple.custom`; managed rows live only in `menus.work.google_apps` and
the configured apps file. The Apps Data File cannot point at the active
`state.json`.

## Configuration Files

The TUI uses these files:

- **`~/.config/sketchybar/state.json`**: Main ignored, per-machine
  configuration and runtime path overrides
- **`~/.config/sketchybar/local.json`**: Legacy path fallback, read only when
  present; new TUI saves do not create or update it

Saving is lossless for state the TUI does not own. Unexposed keys, unknown
future top-level and nested keys, and the existing schema version are preserved
while visible controls are updated. The Raw JSON panel is a read-only preview,
not a second editor; use `--config` or an external editor when you need to
change a key the form does not expose.

Both `state.json` and the legacy `local.json` are gitignored. Runtime path
changes use canonical `paths.code_dir` and `paths.scripts_dir` keys in
`state.json`, matching the Lua runtime's source of truth.

## Environment Variables

Configure paths via environment variables:

```bash
export BARISTA_CONFIG_DIR=~/.config/sketchybar
export BARISTA_CODE_DIR=~/src
export BARISTA_SCRIPTS_DIR=~/.config/sketchybar/scripts
```

You can also override scripts via `state.json` (`paths.scripts_dir` or `paths.scripts`).

## Work Machine Setup

For managed machines where you can't compile binaries:

1. Persist the Lua fallback runtime in state
2. Use the TUI/manual settings path instead of the native GUI
3. Write a machine-local capability profile

```bash
./scripts/setup_machine.sh --yes --profile-variant restricted-work --domain yourcompany.com
./scripts/barista-debug.sh --lua-only --reload
```

`modes.runtime_backend = "lua"` survives reloads, unlike one-off env overrides.
`data/machine.local.json` records which local tools are available.

## Restricted Work Mac Mode

If the machine cannot run yabai or unapproved compiled Barista apps, use the
script-only restricted path instead of the native panel:

```bash
./scripts/setup_machine.sh --yes --restricted-work --domain yourcompany.com
./scripts/barista-debug.sh --lua-only --reload
```

For menu-only edits, use the Python standard-library configurator:

```bash
./scripts/configure_work_google_apps.sh --domain yourcompany.com --replace
python3 ./scripts/restricted_config.py menu-item \
  --label "Runbook" \
  --url "https://example.com/runbook" \
  --section work
```

This path writes `state.json`, `data/machine.local.json`, and
`data/work_apps.local.json` directly. It does not require `jq`, a compiled GUI,
or yabai. If the TUI is unavailable while `runtime_backend` is pinned to `lua`,
the panel launcher opens the state/docs fallback instead of trying the native
GUI.

## Troubleshooting

### TUI won't start

Check Python version and dependencies:
```bash
python3 --version  # Needs 3.9+
pip3 show textual pydantic
```

### Changes not reflected

After saving, reload SketchyBar:
```bash
./plugins/reload_sketchybar.sh
```

Or use `Ctrl+R` in the TUI to save and reload automatically.

### Config file errors

Reset to defaults by removing state.json:
```bash
mv ~/.config/sketchybar/state.json ~/.config/sketchybar/state.json.bak
```
