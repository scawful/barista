# Barista Customization Guide

Ways to tailor the bar without editing core Lua.

## Quick reference

| Goal | Where |
|------|--------|
| Toggle widgets, change colors/fonts | [state.json](#statejson) or [barista_config.lua](CONFIG_OVERRIDES.md) |
| Change profile (Work / Personal / Minimal / Girlfriend) | `./scripts/set_mode.sh <profile> [required\|disabled]` |
| Change theme (colors) | `state.json` → `appearance.theme` or [themes](../features/THEMES.md) |
| Add or edit bar items / popups | [SKETCHYBAR_LAYOUT](../architecture/SKETCHYBAR_LAYOUT.md) → then edit the listed Lua/plugin file |
| Persist overrides that survive GUI/TUI | [barista_config.lua](CONFIG_OVERRIDES.md) |

## state.json

Location: `~/.config/sketchybar/state.json` (or `$BARISTA_CONFIG_DIR/state.json`).

- **widgets** – Turn items on/off: `system_info`, `clock`, `volume`, `battery`, `network`, etc.
- **appearance** – Bar height, padding, colors, fonts, hover animation, popup styling. See `modules/state.lua` defaults for keys (e.g. `bar_height`, `hover_animation_duration`, `font_icon`).
- **icons** – Override icons by name (e.g. `apple`, `clock`, `volume`).
- **profile** – Current profile name; can be set by the GUI/TUI or `set_mode.sh`.

The Control Panel (GUI) and TUI write to `state.json`; edits are applied on the next SketchyBar reload.

## barista_config.lua

For overrides that should **not** be overwritten by the GUI/TUI, use `~/.config/sketchybar/barista_config.lua`. It is loaded after state and profile and deep-merged into state. Supports Lua logic (e.g. hostname-based settings). See [CONFIG_OVERRIDES.md](CONFIG_OVERRIDES.md).

## Profiles

Profiles (Work, Personal, Minimal, Girlfriend) live in `profiles/*.lua` and change density, integrations, and defaults. Switch with:

```bash
./scripts/set_mode.sh personal required   # Personal + yabai
./scripts/set_mode.sh minimal optional   # Minimal, yabai if running
./scripts/set_mode.sh girlfriend disabled # Cozy, no yabai
```

## Themes

`appearance.theme` in state (or `BARISTA_THEME` env) selects a theme from `themes/*.lua`. Optional override: `themes/theme.local.lua`. See [THEMES.md](../features/THEMES.md).

## Fonts

- **Icon font** (`appearance.font_icon`): Used for all bar and popup icons. Default is "Hack Nerd Font". The icon manager falls back by availability (e.g. SF Symbols, Menlo). For best coverage, install a [Nerd Font](https://www.nerdfonts.com/) (e.g. via the installer or `scripts/install_missing_fonts_and_panel.sh`). See [ICON_REFERENCE.md](../features/ICON_REFERENCE.md) for the full icon set.
- **Text / numbers** (`appearance.font_text`, `appearance.font_numbers`): Used for labels and the clock. Change in state or in the Control Panel → Appearance tab.

## Where to edit the bar layout

To add, remove, or change a bar item or its popup, use [docs/architecture/SKETCHYBAR_LAYOUT.md](../architecture/SKETCHYBAR_LAYOUT.md) to find the defining file (e.g. `main.lua`, `modules/items_left.lua`, `modules/items_right.lua`) and the plugin script that updates it.
