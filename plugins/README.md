# Barista Plugins

Shell scripts that SketchyBar invokes for item updates, click actions, and hover behavior.

## Interpreter

Plugins use **bash** or **sh** depending on the script. Scripts that need arrays or `set -euo pipefail` use `#!/bin/bash`; others use `#!/bin/sh` for portability. The shared library [lib/common.sh](lib/common.sh) is written in POSIX sh so it can be sourced from both.

When adding or editing plugins, prefer **POSIX sh** if the script does not need bash features; otherwise use **bash** and document the requirement.

## Environment contract

### Set by SketchyBar when invoking a script

| Variable | Description |
|----------|-------------|
| `NAME` | Item name (e.g. `clock`, `front_app`, `space.1`) |
| `SENDER` | Event that triggered the run (e.g. `mouse.entered`, `mouse.exited`, `front_app_switched`, `volume_change`) |
| `INFO` | Optional event payload (e.g. volume level for `volume_change`, app name for `front_app_switched`) |

### Set by Barista (main.lua or launch env)

| Variable | Description |
|----------|-------------|
| `CONFIG_DIR` | Barista config root (optional; [lib/common.sh](lib/common.sh) sets from `BARISTA_CONFIG_DIR` or default) |
| `BARISTA_CONFIG_DIR` | Override for config root (e.g. when runtime is symlinked or launched by LaunchAgent) |
| `BARISTA_SCRIPTS_DIR` | Override for scripts directory; otherwise read from `state.json` or `CONFIG_DIR/scripts` |
| `BARISTA_HOVER_COLOR` | Hover highlight color (hex, e.g. `0x40f5c2e7`) |
| `BARISTA_HOVER_ANIMATION_CURVE` | Animation curve (e.g. `sin`) |
| `BARISTA_HOVER_ANIMATION_DURATION` | Animation duration in ms (e.g. `12`) |
| `POPUP_HOVER_*` / `SUBMENU_HOVER_*` | For popup/submenu hover scripts; set by main.lua when building the script command |

Widget-specific vars (e.g. `BARISTA_ICON_BATTERY`, `BARISTA_VOLUME_OK`) are set by main.lua per item where needed.

## Shared library (lib/common.sh)

Source it from plugins that need path resolution, hover animation, or timeouts:

```sh
_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"
```

After sourcing you get:

- **CONFIG_DIR**, **STATE_FILE**, **SCRIPTS_DIR** (and `expand_path`)
- **animate_set** – `animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"`
- **run_with_timeout** – `run_with_timeout 1 yabai -m query ...` to avoid hangs

See [lib/common.sh](lib/common.sh) for the full list and defaults.

## Layout and which script runs where

See [docs/architecture/SKETCHYBAR_LAYOUT.md](../docs/architecture/SKETCHYBAR_LAYOUT.md) for which item uses which plugin and which events they subscribe to.
