# SketchyBar Layout Map

Quick reference: which file defines each bar item, which plugin script runs for updates, and which events they subscribe to. Use this to jump to the right place when editing the bar.

**Defining file:** [main.lua](../../main.lua) orchestrates; left-side items are registered in [modules/items_left.lua](../../modules/items_left.lua), right-side items in [modules/items_right.lua](../../modules/items_right.lua). Popup item helpers live in [modules/popup_items.lua](../../modules/popup_items.lua).

---

## Left side (order: left → right)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `popup_manager` | `plugins/popup_manager.sh` | `space_change`, `display_changed`, `display_added`, `display_removed`, `system_woke` | Invisible; handles popup dismissal. It intentionally ignores `front_app_switched` during normal runtime so clicks that cause focus churn do not immediately close the popup that just opened. |
| `space_runtime` | `plugins/space_visuals.sh` | `space_visual_refresh`, `front_app_switched`, `system_woke` | Invisible; single batch visual updater for all spaces. `front_app_switched` runs are coalesced after topology refresh, the focused-space fast path goes through `scripts/front_app_context.sh`, and full visual passes prefer `bin/space_visual_helper` plus `app_icon.sh --batch` for visible app/glyph lookup before one SketchyBar apply. |
| `triforce` | `plugins/oracle_triforce.sh` | `mouse.entered`, `mouse.exited`, `system_woke` | Hover only highlights the anchor, click toggles the popup. The controller delegates status updates to `oos-triforce-widget` when available. |
| `music_studio` | `plugins/music_studio.sh` | `mouse.entered`, `mouse.exited` | Music launcher beside Triforce. Active name comes from `menus.music.item_name`; popup rows are app/workflow/kits launchers from `modules/integrations/music.lua`. Routine updates are disabled; click opening is a direct popup toggle while the plugin only owns hover/status work. |
| `control_center` | `plugins/control_center.sh` | `mouse.entered`, `mouse.exited`, `space_active_refresh`, `space_mode_refresh`, `system_woke` | Default item name. Active name is runtime-resolved; popup focuses on layout actions when yabai is available and Desk/interface-extension rows when yabai is disabled. |
| `front_app` | `plugins/front_app.sh` | `front_app_switched` | Click opens popup (app/window controls). Widget state/location come from `scripts/front_app_context.sh`, which prefers the shared `runtime_context` cache and falls back to current space/display when yabai has no matching managed window. |
| `triforce.*` (popup) | (hover script) | — | Popup rows now use the shared menu-style sizing and hover treatment: title + ROM context, a session section (`Continue`, `Patch + Launch`), and an apps section (`Oracle Hub`, `Yaze`, `z3ed`, `Mesen2 OoS`) with Apple-style headers, separators, and per-app icon colors. The `z3ed` row launches a Ghostty-backed terminal session when Ghostty is installed. |
| `music.studio.*` (popup) | (hover script) | — | Popup rows use the shared menu-style sizing and hover treatment: app launchers (`yams`, `Logic Pro`, `Roland Cloud Manager`, `SP-404MKII App`, and other installed music tools), workflow shortcuts (`Studio Start`, `Plugged In`, `SongForge Board`, PDF guides), and shallow kit/folder launchers (`Samples`, OP-XY/SP-404 starter packs). Action rows close the popup after firing. |
| `front_app.*` (popup) | (hover script) | — | Popup items: state, location, app actions, state-aware window actions, conservative presets, app default set/unset rows, and move actions. When yabai controls are disabled or unavailable, the Window section is replaced by Desk/interface-extension rows. Action rows close the popup after firing. |
| `space.1` … `space.N` | `plugins/space.sh` | `mouse.entered`, `mouse.exited` | Dynamic; created by `plugins/refresh_spaces.sh` → `plugins/simple_spaces.sh`. With yabai unavailable, Barista falls back to `spaces.count` / macOS Spaces preferences / a 5-space default so non-yabai profiles still show a space strip. |
| `space_creator*` | `plugins/space_creator.sh` | `mouse.entered`, `mouse.exited` | Dynamic add-space affordance. Creator items stay display-visible and no longer bind themselves to one associated space. |

Legacy note: the standalone `yabai_status` widget path was removed. Window-manager controls now belong to `control_center` and `front_app` popup rows.

---

## Right side (order: right → left)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `lmstudio` | `plugins/lmstudio_model.sh` | `system_woke` | Optional right-side widget. Personal profiles enable it; work/restricted profiles disable it. The base popup shows current/open/unload actions; model presets are loaded from `interface_extensions` on the `lmstudio` surface. |
| `clock` | `plugins/clock.sh` (or C `clock_widget`) | — | When `modes.widget_daemon` resolves on, routine updates come from `widget_manager daemon`; popup = calendar |
| `clock.calendar.*` | `plugins/calendar.sh` (header) | — | Popup items for calendar plus compact `Today` / `Next` / `Blocked` local task summaries. Clock clicks refresh the popup before opening so date/time/task rows do not stay stale. |
| `ai_resource` | `plugins/ai_resource_toggle.sh` | `ai_resource_update` | AI resource indicator |
| `system_info` | `plugins/system_info.sh` | — | Shell wrapper for hover/events; routine updates prefer compiled helpers or the widget daemon; full popup detail refresh happens on click |
| `system_info.*` (popup) | (hover script) | — | Popup items for system info |
| `volume` | `plugins/volume.sh` | `volume_change` | Click toggles the popup immediately, then refreshes audio/media rows asynchronously through `plugins/volume.sh`; `plugins/volume_click.sh` remains a compatibility wrapper for the same toggle-then-refresh behavior. |
| `volume.*` (popup) | (hover script) | — | Popup items for prefixed `Volume`, `Output`, and `Now Playing` state, output routes, transport controls, mute, and settings. `scripts/media_control.sh` prefers the shared `runtime_context` cache for state/output lookups, and action rows close the popup after firing. |
| `battery` | `plugins/battery.sh` | `system_woke`, `power_source_change` | Shell wrapper for hover/events; routine main-label updates prefer `widget_manager` or the widget daemon; popup detail refresh happens on click |
| `battery.*` (popup) | (hover script) | — | Popup items for battery details. Popup refresh handles AC/charging states explicitly and action rows close the popup after firing. |

---

## Brackets (visual grouping)

- `control_center` + `front_app` (left group)
- `lmstudio` + `clock` + `system_info` (right group when LM Studio is enabled)
- `clock` + `system_info` (right group when LM Studio is disabled)
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

## Popup click path

Normal click-open anchors use direct SketchyBar toggles from `main.lua`'s
`popup_toggle_action()` / `modules/ui_builder.lua`: `sketchybar -m --set <item> popup.drawing=toggle`.
Do not put yabai display-focus queries, detail refresh helpers, or plugin update
controllers in the generic click path; those can make real mouse clicks look
dropped even when script-only tests pass. Use explicit yabai repair/actions for
display focus instead.
`front_app`, `control_center`, Triforce, Music, and right-side refresh popups
are intentionally direct-toggle anchors even though their plugin scripts still
own status updates, hover events, or async detail refresh.
The global popup manager should not subscribe to `front_app_switched`; app focus
can churn while SketchyBar handles a click, which makes menus appear to ignore
the click by opening and immediately closing.
Popup anchors also do not subscribe to `mouse.exited.global` in normal runtime,
and the global popup manager listens to real `space_change` rather than the
visual-only `space_active_refresh`; both events can arrive during the same focus
transition as a click. Use a second click, popup action rows, or real
space/display/wake events to dismiss.
Left-side popup anchors share a filled idle chip and hover-restore style through
`modules/ui_builder.lua` plus `plugins/lib/common.sh`; hover should restore that
configured idle chip instead of clearing the anchor to transparent.

## Events and triggers

- **space_change**, **space_mode_refresh**: Added as sketchybar events in main.lua. Real `space_changed` yabai signals now route through `refresh_spaces.sh`, which emits `space_change` only when the active space truly changed and emits `space_mode_refresh` after active/topology updates.
- **space_visual_refresh**: Added as a dedicated post-topology and on-demand visual refresh event; handled by `space_runtime`.
- **Yabai signals** (space_changed, space_created, space_destroyed, display_*) are wired in main.lua `watch_spaces()` and all point at `refresh_spaces.sh` so cache/lock handling stays in one place.
  If a signal arrives while `refresh_spaces.sh` already owns the topology lock,
  the script writes the pending reason and schedules one delayed follow-up after
  the lock clears, coalescing event bursts into a single final refresh.

---

## Runtime Sidecars

- **`widget_manager daemon`** owns steady-state `clock`, `system_info`, and `battery` updates when the compiled runtime is enabled.
- **`scripts/runtime_context.sh daemon`** owns shared runtime caches under `cache/runtime_context/`.
- **`bin/runtime_context_helper`** owns the hot front-app / focused-space cache path when the compiled helper is present.
- **`scripts/front_app_context.sh`** reads that cache first, then falls back to direct yabai/System Events discovery.
- **`scripts/media_control.sh`** reads cached player/output state first, but still dispatches playback and output-switch actions directly.
- **`scripts/process_manager.sh barista|runaways`** inspects the live process family and flags duplicated/hot Barista plugin scripts without cleanup by default.

---

## Where to edit

- **Bar appearance** (height, padding, colors, fonts): main.lua → appearance/state values and `sbar.bar()` / `sbar.default()`.
- **Add/remove a left-side item:** main.lua (search for `sbar.add("item",` and `position = "left"`) or items_left module after refactor.
- **Add/remove a right-side item:** main.lua (search for `position = "right"`) or items_right module after refactor.
- **Change what a widget does:** Edit the corresponding script in `plugins/` (e.g. `plugins/clock.sh`, `plugins/volume.sh`).
- **Change popup contents:** `modules/items_left.lua` for front-app and Desk extension rows, `modules/integrations/control_center.lua` for Control Center rows, and `modules/items_right.lua` for LM Studio/calendar/system-info rows.
- **Change control-center popup rows:** `modules/integrations/control_center.lua`.
- **Change control-center item placement/wiring:** `modules/items_left.lua` and `main.lua`.
