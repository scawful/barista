# Apple Menu Tools

Barista renders a tools-only Apple menu popup (not the macOS system menu).
Use it for quick access to your apps, web shortcuts, and Barista controls.

## Terms

- `Menu popup`: the full Apple menu opened from the bar.
- `Popup section`: a grouped block of rows inside that menu.
- `Legacy fly-out submenu`: an older hover-open nested popup still used by a few integrations.

Use `popup section` by default when talking about Apple-menu grouping.

## Source of truth

- Edit menu settings in this repo and deploy with `./scripts/deploy.sh`.
- Runtime state lives in `~/.config/sketchybar/state.json`.
- Use the Barista Config Menu tab for common edits (labels, icons, order, toggles).

## Sections

- Apps
- AFS Tools
- Audio
- Core Tools
- Controls
- Web Apps
- Support
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
menus.apps = {
  "enabled": true,
  "file": "data/project_shortcuts.json",
  "default_action": "terminal"
}
```

## Core item IDs

- `afs_browser`, `afs_studio`, `afs_labeler`
- `afs_context`, `afs_scratchpad`
- `stemforge`, `stem_sampler`
- `yaze`, `mesen_oos`, `oracle_agent_manager`
- `cortex_toggle`, `cortex_hub`
- `help_center`, `sys_manual`, `icon_browser`, `keyboard_overlay`, `barista_config`, `reload_bar`

## App shortcuts

- App shortcuts are loaded from `menus.apps.file`, which defaults to `data/project_shortcuts.json`.
- Relative `path` values are resolved from your workspace root (`~/src` unless `paths.code_dir` overrides it).
- `default_action` controls how a path-based row opens when the JSON entry only provides a `path`:
  - `terminal`
  - `finder`
  - `code`
- The Menu tab in the control panel can refresh this file from your local workspace with `Refresh Apps`.
- `menus.projects` is still accepted as a legacy alias, but `menus.apps` is the preferred key now.

## Behavior notes

- Missing tools are hidden unless `show_missing` is enabled.
- Missing/blocked items open Barista Config so you can adjust paths or disable them.
- Terminal-only tools are hidden unless `menus.apple.terminal` is enabled (AFS Studio/Labeler CLI fallbacks honor this).
- Help Center and Icon Browser fall back to docs when binaries are missing; Sys Manual requires the app binary.
- Shortcut glyphs are sourced from `modules/shortcuts.lua` (per-action) and rendered in the menu.
- Hover styles can be overridden via `menus.apple.hover` or env vars:
  `POPUP_HOVER_COLOR`, `POPUP_HOVER_BORDER_COLOR`, `POPUP_HOVER_BORDER_WIDTH`.
- Popup section density is controlled by `appearance.menu_item_height`, `appearance.menu_header_height`, and `appearance.menu_padding`.
- Legacy fly-out submenu timing is controlled by `appearance.submenu_close_delay`.

## AFS app resolution

- **AFS Browser**: ImGui app bundle (override via `AFS_BROWSER_APP`).
  Default: `%CODE%/lab/afs_suite/build/apps/browser/afs-browser.app`
- **AFS Studio/Labeler**: direct binaries in `AFS_STUDIO_ROOT` or `%CODE%/lab/afs/apps/studio`.
  Terminal fallback uses `AFS_ROOT` CLI and requires `menus.apple.terminal = true`.
- **AFS Root**: `AFS_ROOT` env var or `%CODE%/lab/afs`.

## Yaze resolution

- **Repo root**: `BARISTA_YAZE_DIR` or `%CODE%/yaze` (also checks `%CODE%/hobby/yaze`).
- **App override**: `BARISTA_YAZE_APP` or `YAZE_APP`.
- **Nightly prefix**: `BARISTA_YAZE_NIGHTLY_PREFIX` or `YAZE_NIGHTLY_PREFIX` (defaults to `~/.local/yaze/nightly`).
  Barista checks `current/yaze.app` under that prefix.
- **Launcher override**: `BARISTA_YAZE_LAUNCHER` or `YAZE_LAUNCHER`.
  If unset, Barista uses `yaze-nightly` when it exists in `PATH`.
- **Nightly app path**: also checks `~/Applications/Yaze Nightly.app` and `~/applications/yaze nightly.app`.

## Cortex integration

- The menu uses `cortex-cli` for toggle + hub actions.
- Provide it via `PATH` or set `CORTEX_CLI` / `CORTEX_CLI_PATH`.

## Reload

```
sketchybar --reload
```
