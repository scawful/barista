# Apple Menu Tools

Barista renders a tools-only Apple menu popover (not the macOS system menu).
Use it for quick access to apps, utilities, and Barista controls.

## Source of truth

- Edit menu settings in this repo and deploy with `./scripts/deploy.sh`.
- Runtime state lives in `~/.config/sketchybar/state.json`.
- Use the Barista Config Menu tab for common edits (labels, icons, order, toggles).

## Sections

- AFS Tools
- Audio
- Apps
- Cortex
- Barista
- Custom

## Configuration (state.json)

```
menus.apple.show_missing = true|false
menus.apple.terminal = true|false
menus.apple.items.<id>.enabled = true|false
menus.apple.items.<id>.label = "Custom Label"
menus.apple.items.<id>.icon = "<icon>"
menus.apple.items.<id>.icon_color = "0xffa6e3a1"
menus.apple.items.<id>.label_color = "0xffcdd6f4"
menus.apple.items.<id>.order = 10
menus.apple.custom = [
  {
    "label": "My Tool",
    "command": "open -a MyApp",
    "icon": "<icon>",
    "icon_color": "0xff89b4fa",
    "label_color": "0xffcdd6f4",
    "order": 2010,
    "enabled": true,
    "section": "custom"
  }
]
menus.apple.hover = {
  "color": "0x60cdd6f4",
  "border_color": "0xffcdd6f4",
  "border_width": 2
}
```

## Core item IDs

- `afs_browser`, `afs_studio`, `afs_labeler`
- `stemforge`, `stem_sampler`
- `yaze`
- `cortex_toggle`, `cortex_hub`
- `help_center`, `sys_manual`, `icon_browser`, `barista_config`, `reload_bar`

## Behavior notes

- Missing tools are hidden unless `show_missing` is enabled.
- Missing/blocked items open Barista Config so you can adjust paths or disable them.
- Terminal-only tools are hidden unless `menus.apple.terminal` is enabled (AFS Studio/Labeler CLI fallbacks honor this).
- Help Center and Icon Browser fall back to docs when binaries are missing; Sys Manual requires the app binary.
- Shortcut glyphs are sourced from `modules/shortcuts.lua` (per-action) and rendered in the menu.
- Hover styles can be overridden via `menus.apple.hover` or env vars:
  `POPUP_HOVER_COLOR`, `POPUP_HOVER_BORDER_COLOR`, `POPUP_HOVER_BORDER_WIDTH`.

## AFS app resolution

- **AFS Browser**: ImGui app bundle (override via `AFS_BROWSER_APP`).
  Default: `%CODE%/lab/afs_suite/build/apps/browser/afs-browser.app`
- **AFS Studio/Labeler**: direct binaries in `AFS_STUDIO_ROOT` or `%CODE%/lab/afs/apps/studio`.
  Terminal fallback uses `AFS_ROOT` CLI and requires `menus.apple.terminal = true`.
- **AFS Root**: `AFS_ROOT` env var or `%CODE%/lab/afs`.

## Cortex integration

- The menu uses `cortex-cli` for toggle + hub actions.
- Provide it via `PATH` or set `CORTEX_CLI` / `CORTEX_CLI_PATH`.

## Reload

```
sketchybar --reload
```
