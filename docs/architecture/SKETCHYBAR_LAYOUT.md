# SketchyBar Layout Map

Quick reference: which file defines each bar item, which plugin script runs for updates, and which events they subscribe to. Use this to jump to the right place when editing the bar.

**Defining file:** [main.lua](../../main.lua) orchestrates; left-side items are registered in [modules/items_left.lua](../../modules/items_left.lua), right-side items in [modules/items_right.lua](../../modules/items_right.lua). Popup item helpers live in [modules/popup_items.lua](../../modules/popup_items.lua).

---

## Left side (order: left → right)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `popup_manager` | `plugins/popup_manager.sh` | `space_change`, `display_changed`, `display_added`, `display_removed`, `system_woke`, `front_app_switched` | Invisible; handles popup dismissal |
| `space_runtime` | `plugins/space_visuals.sh` | `space_visual_refresh`, `front_app_switched`, `system_woke` | Invisible; single batch visual updater for all spaces. `front_app_switched` runs are coalesced after topology refresh, and the focused-space fast path now goes through `scripts/front_app_context.sh` so the hot path updates only the active visible space instead of snapshotting all windows. |
| `control_center` | `plugins/control_center.sh` | `mouse.entered`, `mouse.exited`, `mouse.exited.global`, `space_change`, `space_mode_refresh`, `system_woke` | Default item name. Active name is runtime-resolved; popup now focuses on layout actions and shortcut state only, and global pointer exit dismisses the popup. |
| `front_app` | `plugins/front_app.sh` | `front_app_switched` | Click opens popup (app/window controls). Widget state/location come from `scripts/front_app_context.sh`, which prefers the shared `runtime_context` cache and falls back to current space/display when yabai has no matching managed window. |
| `triforce` | `plugins/oracle_triforce.sh` | `mouse.entered`, `mouse.exited`, `mouse.exited.global`, `system_woke`, `space_change`, `space_mode_refresh`, `display_changed`, `display_added`, `display_removed` | Hover only highlights the anchor, click toggles the popup, and leaving the popup area dismisses it. The controller delegates status updates to `oos-triforce-widget` when available. |
| `front_app.*` (popup) | (hover script) | — | Popup items: state, location, app actions, window actions, move actions. Action rows close the popup after firing. |
| `space.1` … `space.N` | `plugins/space.sh` | `mouse.entered`, `mouse.exited` | Dynamic; created by `plugins/refresh_spaces.sh` → `plugins/simple_spaces.sh`. Visual state is batch-updated by `space_runtime`, unused per-space popup menu rows are gone, and topology-only reorder changes now update existing `space.*` items in place when possible. |
| `space_creator*` | `plugins/space_creator.sh` | `mouse.entered`, `mouse.exited` | Dynamic add-space affordance. Creator items stay display-visible and no longer bind themselves to one associated space. |

Legacy note: the standalone `yabai_status` widget path was removed. Window-manager controls now belong to `control_center` and `front_app` popup rows.

---

## Right side (order: right → left)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `clock` | `plugins/clock.sh` (or C `clock_widget`) | — | When `modes.widget_daemon` resolves on, routine updates come from `widget_manager daemon`; popup = calendar |
| `clock.calendar.*` | `plugins/calendar.sh` (header) | — | Popup items for calendar |
| `ai_resource` | `plugins/ai_resource_toggle.sh` | `ai_resource_update` | AI resource indicator |
| `system_info` | `plugins/system_info.sh` | — | Shell wrapper for hover/events; routine updates prefer compiled helpers or the widget daemon; full popup detail refresh happens on click |
| `system_info.*` (popup) | (hover script) | — | Popup items for system info |
| `volume` | `plugins/volume.sh` | `volume_change` | Click = `plugins/volume_click.sh`, which refreshes audio/media state before opening and toggles closed on a second click |
| `volume.*` (popup) | (hover script) | — | Popup items for current audio state, output route, now-playing state, transport controls, mute, and settings. `scripts/media_control.sh` prefers the shared `runtime_context` cache for state/output lookups, and action rows close the popup after firing. |
| `battery` | `plugins/battery.sh` | `system_woke`, `power_source_change` | Shell wrapper for hover/events; routine main-label updates prefer `widget_manager` or the widget daemon; popup detail refresh happens on click |
| `battery.*` (popup) | (hover script) | — | Popup items for battery details. Popup refresh handles AC/charging states explicitly and action rows close the popup after firing. |

---

## Brackets (visual grouping)

- `control_center` + `front_app` (left group)
- `clock` + `system_info` (right group)
- `volume` + `battery` (right group)

## Control Center Path

Default runtime path:

1. [main.lua](../../main.lua) resolves the active control-center item name once.
2. [modules/items_left.lua](../../modules/items_left.lua) creates the left-bar item and passes the resolved name into popup creation.
3. [modules/integrations/control_center.lua](../../modules/integrations/control_center.lua) renders the widget and all popup rows against `popup.<item_name>`.
4. `popup_manager` registers the same item name for dismissal behavior.
5. [modules/shortcuts.lua](../../modules/shortcuts.lua) generates `toggle_control_center` against that same resolved target.
6. [modules/popup_action.lua](../../modules/popup_action.lua) attaches helper popups to the resolved control-center popup parent instead of assuming `popup.control_center`.

The default item name is `control_center`. If `integrations.control_center.item_name`
is set in `state.json`, the runtime uses that value consistently across those paths.

---

## Events and triggers

- **space_change**, **space_mode_refresh**: Added as sketchybar events in main.lua. Real `space_changed` yabai signals now route through `refresh_spaces.sh`, which emits `space_change` only when the active space truly changed and emits `space_mode_refresh` after active/topology updates.
- **space_visual_refresh**: Added as a dedicated post-topology and on-demand visual refresh event; handled by `space_runtime`.
- **Yabai signals** (space_changed, space_created, space_destroyed, display_*) are wired in main.lua `watch_spaces()` and all point at `refresh_spaces.sh` so cache/lock handling stays in one place.

---

## Runtime Sidecars

- **`widget_manager daemon`** owns steady-state `clock`, `system_info`, and `battery` updates when the compiled runtime is enabled.
- **`scripts/runtime_context.sh daemon`** owns shared runtime caches under `cache/runtime_context/`.
- **`bin/runtime_context_helper`** owns the hot front-app / focused-space cache path when the compiled helper is present.
- **`scripts/front_app_context.sh`** reads that cache first, then falls back to direct yabai/System Events discovery.
- **`scripts/media_control.sh`** reads cached player/output state first, but still dispatches playback and output-switch actions directly.

---

## Where to edit

- **Bar appearance** (height, padding, colors, fonts): main.lua → appearance/state values and `sbar.bar()` / `sbar.default()`.
- **Add/remove a left-side item:** main.lua (search for `sbar.add("item",` and `position = "left"`) or items_left module after refactor.
- **Add/remove a right-side item:** main.lua (search for `position = "right"`) or items_right module after refactor.
- **Change what a widget does:** Edit the corresponding script in `plugins/` (e.g. `plugins/clock.sh`, `plugins/volume.sh`).
- **Change popup contents:** main.lua (search for `add_front_app_popup_item`, `add_volume_popup_item`, `add_battery_popup_item`, or calendar/system_info item loops).
- **Change control-center popup rows:** `modules/integrations/control_center.lua`.
- **Change control-center item placement/wiring:** `modules/items_left.lua` and `main.lua`.
