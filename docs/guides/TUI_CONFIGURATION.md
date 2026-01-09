# Barista TUI Configuration Guide

The `barista` command provides a terminal-based user interface (TUI) for configuring your SketchyBar status bar. No compilation required - it works on any machine with Python 3.9+.

## Quick Start

```bash
# From the barista repository
cd ~/src/lab/barista
./bin/barista

# Or if barista/bin is in your PATH
barista
```

## CLI Fallbacks (No GUI Build)

If you can’t build the native GUI on a machine, you can still update `state.json` using the TUI or the CLI scripts.

### TUI (preferred)

```bash
bin/open_control_panel.sh --tui
# Or force the fallback:
export BARISTA_TUI_ONLY=1
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
sketchybar --reload
```

## Requirements

- Python 3.9+
- textual (TUI framework)
- pydantic (config validation)

Install dependencies:
```bash
pip install -r requirements.txt
# Or: pip install textual pydantic pyyaml
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

Also configure which items appear in the System Info popup.

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
- **Google**: Google Workspace

Also configure custom paths for your machine.

### Advanced

- **Font Settings**: Configure icon, text, and number fonts
- **Feature Toggles**: Enable/disable Yabai shortcuts
- **Raw JSON**: Edit the configuration directly

## Configuration Files

The TUI edits these files:

- **`~/.config/sketchybar/state.json`**: Main configuration
- **`~/.config/sketchybar/local.json`**: Machine-specific paths (optional)

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

1. Install Python dependencies: `pip install textual pydantic`
2. Set `BARISTA_LUA_ONLY=1` to skip C helpers
3. Use the TUI instead of the native GUI

```bash
# In your shell config
export BARISTA_LUA_ONLY=1

# Configure paths if different
export BARISTA_CODE_DIR=~/google3
```

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
sketchybar --reload
```

Or use `Ctrl+R` in the TUI to save and reload automatically.

### Config file errors

Reset to defaults by removing state.json:
```bash
mv ~/.config/sketchybar/state.json ~/.config/sketchybar/state.json.bak
```
