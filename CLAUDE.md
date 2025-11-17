# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a modular SketchyBar configuration written in Lua with Yabai integration. It provides a modern macOS status bar with interactive widgets, hover popups, nested menus, and dynamic theming.

## Build Commands

### Compile Performance-Critical C/C++ Helpers
```bash
cd helpers && make && make install
```
This compiles and installs optimized binaries for:
- `clock_widget` - Fast clock rendering
- `system_info_widget` - CPU/memory/disk monitoring
- `space_manager` - Quick space operations
- `submenu_hover` - Menu hover handling
- `popup_anchor` - Popup positioning
- `menu_action` - Menu action dispatcher

### Build Objective-C GUI Tools
```bash
cd gui && make
```
Builds:
- `config_menu` - Main control panel for settings
- `icon_browser` - Nerd Font icon picker
- `help_center` - Documentation viewer

### Reload Configuration
```bash
sketchybar --reload
```

## Architecture

### Entry Point
- `sketchybarrc` - Shell wrapper that launches `main.lua`
- `main.lua` - Main configuration file that orchestrates the entire bar

### Module System
Located in `modules/`:

**State Management** (`state.lua`)
- Centralized JSON-based persistence at `~/.config/sketchybar/state.json`
- Handles widget visibility, appearance settings, per-space icons/modes, integration toggles
- Auto-sanitizes corrupted state on load
- Key functions: `state.load()`, `state.save()`, `state.get()`, `state.update()`

**Widget Factory** (`widgets.lua`)
- Factory pattern for creating widgets with consistent styling
- Reads appearance values (bar height, corner radius, widget scale) from state
- Automatically scales fonts/padding based on `widget_scale` (0.85-1.25)
- Creates: clock, battery, volume, network, system_info widgets

**Menu System** (`menu.lua`)
- Renders Apple menu and front-app menus from JSON definitions
- Loads menu sections from `data/*.json` files
- Supports nested submenus with hover detection
- Wraps actions through `menu_action` dispatcher for async execution

**Icon Library** (`icons.lua`)
- Curated Nerd Font icon library organized by categories
- Used as fallback when state doesn't provide custom icon

**Integration Modules** (`modules/integrations/`)
- `yaze.lua` - ROM hacking workflow integration
- `emacs.lua` - Emacs workspace integration
- `whichkey.lua` - Keybinding HUD overlay

### Theme System
- `theme.lua` - Loads theme from `themes/` directory
- Set `current_theme` variable to switch themes
- Each theme returns a Lua table with color definitions (Catppuccin-based)

### Plugin Scripts
Located in `plugins/`:
- Shell scripts that provide data to bar items
- Most performance-critical ones have C implementations in `helpers/`
- Examples: `battery.sh`, `clock.sh`, `front_app.sh`, `system_info.sh`

### C/C++ Helpers
Located in `helpers/`:
- Low-CPU alternatives to shell scripts for frequently-updating widgets
- Built with `cd helpers && make install`
- Configuration automatically falls back to shell scripts if binaries missing

### GUI Tools
Located in `gui/`:
- Objective-C Cocoa applications for visual configuration
- Built with `cd gui && make`
- Launched via Apple menu or by Shift+clicking Apple icon

## State Management

State is stored at `~/.config/sketchybar/state.json` and includes:

```lua
{
  widgets = { clock = true, battery = true, ... },
  appearance = {
    bar_height = 28,
    corner_radius = 0,
    bar_color = "0xC021162F",
    blur_radius = 30,
    widget_scale = 1.0,
  },
  icons = { apple = "", ... },
  space_icons = { ["1"] = "", ... },
  space_modes = { ["2"] = "bsp", ["3"] = "stack" },
  widget_colors = { clock = "0x...", ... },
  integrations = {
    yaze = { enabled = true, recent_roms = [] },
    emacs = { enabled = true, workspace_name = "Emacs" }
  }
}
```

## Yabai Integration

The configuration deeply integrates with Yabai window manager:

- Yabai signals trigger space refreshes via `plugins/refresh_spaces.sh`
- `plugins/spaces_setup.sh` rebuilds space items on space/display changes
- Each space can have custom icon and mode (float/bsp/stack)
- Space modes stored in state and applied on space change
- External bar height sync via `~/.config/scripts/update_external_bar.sh`

## Adding New Widgets

1. Add widget to `widgets.lua` factory (optional - for common patterns)
2. Create plugin script in `plugins/` (shell) or `helpers/` (C)
3. Add widget creation in `main.lua`
4. Subscribe to relevant events with `sbar.exec("sketchybar --subscribe ...")`
5. Add to default state in `modules/state.lua` if it should be toggleable

## Adding Menu Items

1. Edit or create JSON file in `data/` (e.g., `data/menu_help.json`)
2. Load in menu module with `load_menu_section(ctx, "menu_help")`
3. Menu items support:
   - `action` - Command to execute on click
   - `submenu` - Array of nested items
   - `icon`, `label`, `shortcut` - Display properties
   - `type` - "header", "separator", or default (clickable)

## Modifying Themes

1. Edit existing theme in `themes/default.lua` or create new file in `themes/`
2. Theme must return table with color definitions (use hex strings like "0xFFFFFFFF")
3. Update `current_theme` in `theme.lua` to switch
4. Reload bar to apply changes

## Important Patterns

**Widget Scaling**: All font sizes and padding automatically scale based on `widget_scale` state value. Use `scaled(value)` helper when adding new widgets.

**Popup Management**: Popups require subscription to auto-close events:
```lua
subscribe_popup_autoclose("widget_name")
```

**Icon Resolution**: Icons are resolved in order:
1. Custom icon from state (`state_module.get_icon()`)
2. Icon library (`icons_module.find()`)
3. Fallback provided in code

**Shell Execution**: Always use `shell_exec()` wrapper which properly quotes bash commands and uses login shell.

## Persistent Paths

- Config: `~/.config/sketchybar/`
- State: `~/.config/sketchybar/state.json`
- Compiled helpers: `~/.config/sketchybar/bin/`
- Scripts: `~/.config/scripts/`
- Icon map: `~/.config/sketchybar/icon_map.json`

## Documentation

- `README.md` - Feature overview and user guide
- `HANDOFF.md` - Detailed handoff notes
- `docs/SHARING.md` - Onboarding flow for new users
