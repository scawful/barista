# Barista State Schema

`state.json` is Barista's runtime configuration file.

- Default values and migrations live in [modules/state.lua](../modules/state.lua).
- Shared read-only lookup for menus and shortcuts lives in [modules/tool_locator.lua](../modules/tool_locator.lua).
- Runtime location: `~/.config/sketchybar/state.json` or `$BARISTA_CONFIG_DIR/state.json`.

## Example

```json
{
  "profile": "personal",
  "widgets": {
    "clock": true,
    "battery": true
  },
  "appearance": {
    "theme": "default",
    "bar_height": 28,
    "hover_animation_duration": 8
  },
  "modes": {
    "window_manager": "optional",
    "runtime_backend": "lua",
    "widget_daemon": "auto"
  },
  "paths": {
    "scripts_dir": "/Users/you/.config/sketchybar/scripts",
    "code_dir": "/Users/you/src"
  },
  "menus": {
    "apple": {
      "show_missing": false,
      "terminal": false,
      "items": {
        "yaze": { "enabled": true }
      }
    },
    "oracle": {
      "sections": {
        "play": { "enabled": true }
      },
      "triforce": {
        "label": "",
        "icon": "",
        "update_freq": 45
      }
    },
    "apps": {
      "enabled": true,
      "file": "data/project_shortcuts.json",
      "default_action": "terminal"
    },
    "work": {
      "workspace_domain": "example.com"
    }
  },
  "integrations": {
    "yaze": { "enabled": true }
  }
}
```

## Top-Level Keys

| Key | Type | Purpose |
|-----|------|---------|
| `_version` | number | State schema version used by migrations. |
| `profile` | string | Active profile name (`minimal`, `girlfriend`, `work`, `personal`). |
| `widgets` | object | Per-widget enable/disable flags. |
| `appearance` | object | Bar, popup, font, hover, and grouping appearance settings. |
| `icons` | object | Named icon overrides such as `apple`, `wifi`, `volume`. |
| `widget_colors` | object | Per-widget color overrides. |
| `space_icons` | object | Custom icon per space number. |
| `space_modes` | object | Saved layout mode per space number. |
| `spaces` | object | Space-management behavior toggles. |
| `system_info_items` | object | Controls which system-info popup rows are shown. |
| `modes` | object | Runtime mode switches such as window manager and backend selection. |
| `toggles` | object | Simple persisted toggles, for example yabai shortcut enablement. |
| `paths` | object | Runtime path overrides. |
| `menus` | object | Apple-menu popup sections, app shortcuts, and web-app shortcut configuration. |
| `integrations` | object | Per-integration enablement and metadata. |

## Important Nested Keys

### `appearance`

Common keys:

- `theme`
- `bar_height`
- `widget_scale`
- `auto_more_space_scaling`
- `more_space_widget_scale_boost`
- `menu_item_height`, `menu_header_height`, `menu_padding`
- `menu_item_corner_radius`, `menu_font_style`, `menu_header_font_style`, `menu_font_size_offset`
- `bar_padding_left`, `bar_padding_right`, `bar_margin`, `bar_y_offset`
- `popup_padding`, `popup_corner_radius`, `popup_border_width`, `popup_bg_color`
- `hover_color`, `hover_border_color`, `hover_animation_curve`, `hover_animation_duration`
- `submenu_hover_color`, `submenu_idle_color`, `submenu_close_delay`
- `submenu_hover_corner_radius`, `submenu_hover_padding_left`, `submenu_hover_padding_right`
- `font_icon`, `font_text`, `font_numbers`

`widget_scale` is the manual baseline. When `auto_more_space_scaling` is enabled, Barista detects a built-in display running a downscaled macOS "More Space" mode, raises the effective bar height to match the top inset when needed, and adds `more_space_widget_scale_boost` on top of the widget baseline.

Menu popup rows are separate from the bar now: `menu_item_height`, `menu_header_height`, and `menu_padding` control popup density without changing the bar height.

Barista uses two menu terms deliberately:

- `popup section` means a grouped block of rows inside a popup.
- `legacy fly-out submenu` means a nested hover-open popup attached to a row.

See [GLOSSARY.md](GLOSSARY.md) for the short version.

The full default set is defined in [modules/state.lua](../modules/state.lua).

### `modes`

Supported keys:

- `window_manager`: `disabled`, `optional`, `required`, or `auto`
- `runtime_backend`: `lua`, `compiled`, or `auto`
- `widget_daemon`: `auto`, `enabled`, or `disabled`

### `paths`

Common supported keys:

- `scripts_dir`
- `code_dir` or `code`

`tool_locator.lua` prefers explicit runtime context first, then env vars, then persisted path overrides, then built-in defaults.

### `menus.apple`

Supported keys used by the Apple menu:

- `show_missing`
- `terminal`
- `launch`
- `items.<id>.enabled`
- `items.<id>.label`
- `items.<id>.icon`
- `items.<id>.icon_color`
- `items.<id>.label_color`
- `items.<id>.order`
- `custom[]`
- `custom[].items[]`
- `hover.color`
- `hover.border_color`
- `hover.border_width`
- `sections.<section_id>.label`
- `sections.<section_id>.icon`
- `sections.<section_id>.color`
- `sections.<section_id>.order`

This config controls Apple-menu popup sections. Legacy fly-out submenu behavior is driven mostly by `appearance.submenu_*`.

Each `menus.apple.custom[]` entry can be either:

- a single action row with `label`, `command`/`action`, optional `icon`, `shortcut`, and `section`
- a nested fly-out group with `items[]`

Nested `items[]` rows support:

- `type = "header"`
- `type = "separator"`
- standard rows with `label`, `command`/`action`, `url`, `icon`, `shortcut`, and optional nested `items[]`

### `menus.oracle`

Supported keys:

- `sections.<section_id>.enabled`
- `sections.<section_id>.label`
- `sections.<section_id>.order`
- `sections.<section_id>.limit`
- `triforce.label`
- `triforce.icon`
- `triforce.title`
- `triforce.show_label`
- `triforce.update_freq`

Known section ids:

- `play`

This config drives the standalone Zelda hacking surface:

- the left-bar `Triforce` widget popup
- the native Barista control-panel `Zelda` tab as its status source

Section visibility and ordering shape the shallow Triforce popup. In the current design, `play` is the only primary launcher section and the native Zelda tab owns the deeper workflow detail.

Notes:

- `menus.oracle` still configures the bar-facing Zelda surface, not the full native panel layout.
- The native Zelda tab reads the same Oracle status snapshot (`scripts/oos_status.py`) but does not currently add its own persisted state keys.
- Oracle status items like `today`, `next`, and `blocked` still exist in the status snapshot for the native panel, but they no longer create nested Triforce popup sections.
- `open_control_panel.sh --oracle` forwards to Oracle Hub.

### `menus.apps`

Supported keys:

- `enabled`
- `file`
- `default_action`
- `items[]`

`file` usually points at `data/project_shortcuts.json`, which stores app shortcut rows for the `Apps` popup section.

Each app shortcut item can define:

- `id`
- `label`
- `path`
- `icon`
- `icon_color`
- `label_color`
- `order`
- `section`
- `shortcut`
- `open_mode` (`terminal`, `finder`, or `code`)
- `action` (explicit shell command override)

`menus.projects` is still supported as a legacy alias and is merged into `menus.apps` automatically.

### `menus.work`

Supported keys:

- `google_apps`
- `apps_file`
- `workspace_domain`

These render as web-app shortcuts inside a popup section. The historical state key is still `google_apps`, but the UI now labels them `Web App Shortcuts`.

### `integrations`

Each integration entry is a free-form object.

Barista currently expects an `enabled` boolean for feature gating, for example:

```json
{
  "integrations": {
    "yaze": { "enabled": true },
    "oracle": { "enabled": false }
  }
}
```

Known integration-specific keys used by the active runtime:

- `integrations.control_center.enabled`
- `integrations.control_center.item_name`

`integrations.control_center.item_name` is optional. When set, Barista uses it as
the shared item name for:

- the left-bar control-center widget
- popup-parent registration and dismissal
- helper popup attachment that targets the control center
- the generated `toggle_control_center` shortcut command

## Notes

- GUI and TUI tools write to `state.json`; `barista_config.lua` is the right place for machine-specific overrides you do not want overwritten.
- If you add new persisted keys, update both [modules/state.lua](../modules/state.lua) defaults and this document.
