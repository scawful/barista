# SketchyBar Layout Map

Quick reference: which file defines each bar item, which plugin script runs for updates, and which events they subscribe to. Use this to jump to the right place when editing the bar.

**Defining file:** [main.lua](../../main.lua) orchestrates; left-side items are registered in [modules/items_left.lua](../../modules/items_left.lua), right-side items in [modules/items_right.lua](../../modules/items_right.lua). Popup item helpers live in [modules/popup_items.lua](../../modules/popup_items.lua).

---

## Left side (order: left → right)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `popup_manager` | `plugins/popup_manager.sh` | `space_change`, `display_changed`, `display_added`, `display_removed`, `system_woke`, `front_app_switched` | Invisible; handles popup dismissal |
| `control_center` | `plugins/control_center.sh` | `mouse.entered`, `mouse.exited`, `space_change`, `space_mode_refresh`, `system_woke` | Only when integration enabled; bracket with `front_app` |
| `front_app` | `plugins/front_app.sh` | `front_app_switched` | Click opens popup (app/window controls) |
| `front_app.*` (popup) | (hover script) | — | Popup items: header, show/hide/quit, window controls, move |
| `space.1` … `space.N` | `plugins/space.sh` | (per-item: `space_change`, `space_mode_refresh` via triggers) | Dynamic; created by `plugins/refresh_spaces.sh` → `plugins/simple_spaces.sh` |

---

## Right side (order: right → left)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `clock` | `plugins/clock.sh` (or C `clock_widget`) | — | `update_freq` 30s; popup = calendar |
| `clock.calendar.*` | `plugins/calendar.sh` (header) | — | Popup items for calendar |
| `ai_resource` | `plugins/ai_resource_toggle.sh` | `ai_resource_update` | AI resource indicator |
| `system_info` | `plugins/system_info.sh` | — | Popup = CPU/mem/disk/net/etc. |
| `system_info.*` (popup) | (hover script) | — | Popup items for system info |
| `volume` | `plugins/volume.sh` | `volume_change` | Click = `plugins/volume_click.sh` |
| `volume.*` (popup) | (hover script) | — | Popup items for volume levels |
| `battery` | `plugins/battery.sh` | `system_woke`, `power_source_change` | Popup = battery details |
| `battery.*` (popup) | (hover script) | — | Popup items for battery |

---

## Brackets (visual grouping)

- `control_center` + `front_app` (left group)
- `clock` + `system_info` (right group)
- `volume` + `battery` (right group)

---

## Events and triggers

- **space_change**, **space_mode_refresh**: Added as sketchybar events in main.lua; triggered by yabai signal actions and `refresh_spaces.sh`.
- **Yabai signals** (space_changed, space_created, space_destroyed, display_*) are wired in main.lua `watch_spaces()` and point at `refresh_spaces.sh` or trigger the events above.

---

## Where to edit

- **Bar appearance** (height, padding, colors, fonts): main.lua → appearance/state values and `sbar.bar()` / `sbar.default()`.
- **Add/remove a left-side item:** main.lua (search for `sbar.add("item",` and `position = "left"`) or items_left module after refactor.
- **Add/remove a right-side item:** main.lua (search for `position = "right"`) or items_right module after refactor.
- **Change what a widget does:** Edit the corresponding script in `plugins/` (e.g. `plugins/clock.sh`, `plugins/volume.sh`).
- **Change popup contents:** main.lua (search for `add_front_app_popup_item`, `add_volume_popup_item`, `add_battery_popup_item`, or calendar/system_info item loops).
