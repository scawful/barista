# Widget Fixes & C Performance Widgets

## Issues Fixed

### 1. Submenu Hover Behavior (plugins/submenu_hover.sh)
**Problem**: Submenus dismissed too easily and had no visible highlight

**Solution**:
- Removed all delay-based logic and hover state checking
- Changed behavior to only close on `mouse.exited.global` event
- Increased highlight opacity from 30% to 50% (`0x80cba6f7`)
- Added rounded corners (6px) for modern appearance
- Removed `mouse.exited` handling entirely - prevents accidental dismissal

**Result**: Submenus stay open when moving between menu items, only close when mouse leaves entire menu area

### 2. Duplicate CPU Icons (plugins/system_info.sh)
**Problem**: CPU widget showed two CPU icons - one in main widget, one in popup label

**Solution**:
- Metric labels contain text only; glyphs stay in the SketchyBar item `icon`
  property.
- `modules/items_right.lua` passes configured icon overrides to the native and
  shell refreshers, so the two paths keep the same presentation.
- The current CPU detail format is `CPU Usage: 12% (Load: 1.50)`.

**Before**:
```
Main: 󰍛 12%
Popup: 󰍛 CPU 12%    󰓅 Load 1.5  ❌ Double icon
```

**After**:
```
Main: 󰍛 12% 11/32G
Popup: CPU Usage: 12% (Load: 1.50)  ✅ Clean
```

Current compact main-label path:
- The `system_info` bar label is intentionally compact again: `CPU% used/totalG`.
- Verbose details remain in popup rows; the bar label should stay glanceable.
- Default compiled setups let `widget_manager daemon` update the main
  `system_info` item. Daemon-disabled compiled setups retain the routine
  `system_info_widget`; neither path targets popup rows.
- A click toggles the popup immediately, then prefers
  `system_info_popup_helper popup_refresh` asynchronously. The native alias
  updates only the enabled dynamic rows in one bounded Mach payload;
  `plugins/system_info.sh popup_refresh` is the strict portable/failure
  fallback. Routine updates must not target optional popup rows such as
  `system_info.cpu`.

### 3. Clock Icon Missing (plugins/clock.sh)
**Problem**: Clock icon wasn't displaying

**Solution**:
- Added comment clarifying that clock.sh only updates label
- Icon is configured in main.lua via widgets module (`icon = ""`)
- Shell script preserves icon by only setting `label=`

**Config** (modules/widgets.lua:106):
```lua
icon = "",  -- Clock icon
```

### 4. Clock Font Styling (main.lua)
**Problem**: "Medium" font weight not mapped in style_map

**Solution**:
- Added "Medium" to font style_map
- Reordered alphabetically for clarity

**Before**:
```lua
style_map = {
  Regular = "Regular",
  Bold = "Bold",
  Heavy = "Heavy",
  Semibold = "Semibold"
}
```

**After**:
```lua
style_map = {
  Regular = "Regular",
  Medium = "Medium",      -- ✅ Added
  Semibold = "Semibold",
  Bold = "Bold",
  Heavy = "Heavy"
}
```

### 5. Window Manager Widget Path
**Current path**: `plugins/control_center.sh` + `modules/integrations/control_center.lua`
- Window-manager status label is rendered by `control_center` (`BSP`, `Stack`, `Float`, or fallback).
- Space/window actions are exposed in the `control_center` popup and `front_app` popup rows.
- The fully enabled `control_center` root is intentionally slim: its 12 rows keep window-manager mode, space layout, and shortcut controls direct. The click-only `cc.more` / `More Layout Controls` child holds the 11 Layout Ops and App Defaults rows; service-health, dirty-repo, and utility rows remain removed from the live path.
- Opening or closing the root resets `cc.more`, and an action in that child closes both popup levels after it runs. Disabled and no-Yabai paths omit the child and its popup-manager registry entry.
- `control_center` follows the click-open popup-anchor contract; pointer hover only highlights, and dismissal is via second-click, popup actions, or global space/display/wake dismissal.
- The active item name is resolved once and reused by `main.lua`, `items_left.lua`,
  `shortcuts.lua`, and `popup_action.lua`; `items_left.lua` reports the actually
  created anchor name for `popup_manager` registration.
- The popup starts with lightweight mode rows (`Yabai On`, `Auto If Running`, `Manual Bar`) that update `modes.window_manager` through `yabai_control.sh wm-mode ...` and reload through Barista's serialized reload path.
- Config construction never waits on a Yabai layout query. The anchor can briefly show `---` after reload until the existing timeout-bounded post-config refresh publishes `BSP`, `Stack`, or `Float`.
- Default item name: `control_center`.
- Optional override: `integrations.control_center.item_name` in `state.json`.

Legacy note: the old `plugins/yabai_status.sh` widget path is retired from the live layout.

### 6. Space Icon Runtime
**Current path**: `plugins/refresh_spaces.sh` + `plugins/simple_spaces.sh` + `plugins/space_visuals.sh` + `bin/space_visual_helper` + `scripts/app_icon.sh`
- Space topology presence checks now read one bar snapshot instead of calling `sketchybar --query` once per space item.
- Topology add/remove changes now update `space.*` incrementally instead of dropping and recreating the full spaces stack.
- `refresh_spaces.sh` now records explicit topology strategy counters (`full_rebuild`, `creator_only`, `incremental_reorder`, `incremental_add_remove`) into `barista-stats.sh`.
- `space_creator.<display>` buttons carry the current space-index list for their concrete `associated_display` and keep `ignore_association=off`; each stays visible across its target display's spaces without duplicating onto every monitor.
- Visible-space app glyphs are cached under `~/.config/sketchybar/cache/app_glyphs`.
- The glyph cache is versioned; when Barista changes built-in app aliases it automatically clears stale app and space icon cache entries on the next visual refresh.
- `space_visuals.sh` now parses `space_icons` and `space_modes` with a non-whitespace field separator so layout modes like `bsp` cannot leak into the rendered space glyphs when a space has no explicit icon override.
- `space_visuals.sh` now refreshes hidden-space icons from the current yabai window snapshot instead of showing stale cached app glyphs from an old visible state.
- Space highlighting now follows the actually focused space, not every visible space and not the last stale fast-path selection.
- The `front_app_switched` fast path now depends on a fresh `focused-space` record instead of reusing stale cached front-app state.
- `space_visuals.sh` now caches the `space.*` item lookup under `cache/space_visuals/space_items` and reuses it on the `front_app_switched` fast path, so focused visual refreshes do not query the full bar again once topology has already established the active space items.
- `refresh_spaces.sh` now hands its current spaces payload directly to `space_visuals.sh`, so topology-triggered visual refreshes no longer pay for a second `yabai query --spaces`.
- `space_active_refresh` now shares the focused-space fast path with `front_app_switched`, so an active-space-only refresh does not fall back to the full spaces/windows snapshot path.
- Active-space updates now use the dedicated `space_active_refresh` event instead of the older broad `space_change` fan-out, so only the popup-manager and control-center consumers still wake up on focused-space changes.
- `refresh_spaces.sh` no longer emits a redundant `space_mode_refresh` on pure active-space changes.
- `refresh_spaces.sh` now uses the live SketchyBar bar height when repairing yabai `external_bar`, avoiding stale 28px reservations when display-profile scaling raises the rendered bar to a taller height.
- The delayed startup visual sync now runs as `startup_sync` and uses its own wider cooldown window, so reload should not show an extra follow-up visual pass unless the topology path really missed.
- `space_visuals.sh` now resolves visible-space apps with scoped window data instead of a single global window snapshot. When `bin/space_visual_helper` is available, one helper invocation batches those visible-space app lookups and avoids per-space shell/jq parsing; missing app glyphs then resolve through one `app_icon.sh --batch` call before the SketchyBar apply.
- `space_runtime` now keeps `updates=false`, `space_visuals.sh` ignores `forced` sender runs, and `space.sh` no longer falls back to a forced batch refresh on hover-exit cache misses. That removes redundant `sender=forced` visual passes during reload.
- Space and visual scripts preserve the resolved SketchyBar binary from `plugins/lib/common.sh`; do not re-run `command -v sketchybar` after sourcing common, because the shared wrapper function can otherwise recurse and leave hot `space.sh` processes behind.
- The Triforce anchor no longer subscribes to space/display churn events that it never handled, so active-space changes do not wake it up unnecessarily.
- `plugins/space.sh` now caches and restores each item’s real pre-hover colors instead of trusting SketchyBar’s `SELECTED` flag on `mouse.exited`; that prevents multi-display visible spaces from repainting themselves as selected and fighting the centralized `space_visuals.sh` pass.
- `plugins/lib/space_style.sh` now defines focused, visible-inactive, idle, and hover styles. `space_visuals.sh` writes the full per-space style state under `cache/space_visuals/style_state/`, and `space.sh` restores from that state after hover instead of guessing from `last_selected_space`.
- `space_visuals.sh` caches focused/visible/idle style argument arrays once per run, batches helper-backed visible app/glyph lookup when available, skips rewriting unchanged style-state files, and can emit detailed phase fields when run with `BARISTA_SPACE_VISUAL_PHASE_METRICS=1`; those fields appear under `Space visual refreshes` in `barista-stats.sh show`.
- The focused style is a filled lavender pill with a white border; inactive visible spaces keep a stronger dark pill with a subtle border; hidden idle spaces keep the dark chip.
- `Ghostty` now resolves to a terminal glyph instead of the retired `F02A0` codepoint.
- Lowercase app names that show up in yabai output now resolve correctly too (`ghostty`, `spotify`, `firefox`, `messages`, `antigravity`, `cursor`).
- `LM Studio` now resolves to an explicit AI/model glyph instead of the generic fallback.
- Oracle workflow apps (`Oracle Hub`, `Oracle Agent Manager`, `oracle_manager_gui`, `oracle_hub`) resolve to the live Triforce glyph `󰯙`.
- Focused `front_app_switched` refreshes now resolve current space/app context through `scripts/front_app_context.sh` instead of parsing the focused-space JSON inline inside `space_visuals.sh`.

If a space falls back to empty/default icons unexpectedly:
```bash
bash -n ~/.config/sketchybar/plugins/space_visuals.sh
~/.config/sketchybar/bin/barista-stats.sh show
~/.config/sketchybar/scripts/process_manager.sh runaways
sketchybar --reload
```

### 7. Triforce Anchor Interaction
**Current path**: `modules/integrations/oracle.lua` + `plugins/oracle_triforce.sh`
- The left-bar Triforce anchor uses a direct SketchyBar popup toggle for click-open.
- `plugins/oracle_triforce.sh` owns hover highlight and asynchronous status updates, not click-open popup ownership.
- Hover only highlights the anchor; it does not open the popup.
- Click toggles the popup open or closed first, then refreshes dynamic fields in the background from `Scripts/Build/oos-triforce.sh status-json --barista`.
- Triforce has no periodic timer. Post-config, anchor-click, and `system_woke` refreshes apply the anchor plus ROM/focus/Continue targets in one SketchyBar request; malformed status applies nothing.
- Status refreshes coalesce to one worker. The canonical producer has a four-second default deadline and TERM/forced-kill cleanup, preventing click bursts or a stuck Oracle subprocess from accumulating runaways.
- A configured `triforce.label` remains fixed; only `auto`/empty labels follow the live Oracle status line.
- The machine-local `oos-triforce-widget` is only a fallback when the canonical Oracle producer is unavailable.
- Normal runtime no longer subscribes the anchor to `mouse.exited.global`; second-click, popup action rows, and global space/display/wake dismissal close it.
- Popup action rows still close the popup after firing.

### 7b. Popup Click Reliability
**Current path**: `main.lua` `popup_toggle_action()`
- Menu anchor click scripts use direct SketchyBar popup toggles from `main.lua`
  / `modules/ui_builder.lua`:
  `sketchybar -m --set <item> popup.drawing=toggle`.
- Reason: the focus helper queries yabai on every click; when yabai authorization is stale, that can block menu clicks or spawn macOS Developer Tools Access prompts.
- Keep display-focus repair explicit in yabai tooling, not in the hot click path for Apple/Control Center/front-app/right-side menus.
- Do not route `front_app`, `control_center`, Triforce, Music, or right-side
  refresh-popup click opening through their update plugins. Those scripts own
  status/hover/detail work; the anchor click itself should stay a direct toggle
  generated by `popup_toggle_action(<item>)` or `ui.toggle_then_refresh_async(...)`.
- Do not add wrapper helpers for generic anchors unless physical clicks have been validated. Script-only tests can pass even when the mouse event never reaches the item.
- The live bar geometry should stay explicit and stable: `topmost=off`, `bar_y_offset=0`. Do not force `topmost=on` to debug clicks; it can cover native macOS menus.
- The global popup manager no longer dismisses on `front_app_switched` by default. App-focus churn can fire while clicking SketchyBar itself, which made some popups open and immediately close. Space/display/wake events still dismiss globally.
- Popup anchors no longer subscribe to `mouse.exited.global` in normal runtime. This trades automatic pointer-exit dismissal for reliable click-open behavior; second-click, action rows, and space/display/wake events still close menus.
- The global popup manager dismisses on real `space_change`, not visual-only `space_active_refresh`; focused-space visual repairs should not close a popup that was just opened.
- Left-side popup anchors use a shared dark idle chip style from
  `modules/ui_builder.lua`. The native `popup_anchor` helper and shell plugins
  consume the same `BARISTA_ANCHOR_*` values to restore configured idle
  background/border props instead of clearing the background, so Apple,
  Triforce, Music, Control Center, and Front App keep the same geometry after
  hover.
- Native-helper setups resolve the Apple anchor to `bin/popup_anchor`; Lua-only
  and helper-missing setups retain `plugins/popup_anchor.sh`. Popup action-row
  hover uses direct-argv `bin/popup_hover` rather than a nested shell command.

Regression checklist before declaring popup clicks fixed:
```bash
sketchybar --query bar | jq '{topmost,height,y_offset,drawing}'
for item in apple_menu front_app control_center clock system_info volume battery; do
  sketchybar --query "$item" | jq -r '.name + " click=" + .scripting.click_script'
done
```
Expected: click scripts are direct
`sketchybar -m --set "<item>" popup.drawing=toggle` commands, not
`BARISTA_*_ACTION=click ...`.

### 7c. Popup Registry Test Isolation

`tests/test_submenu_registry.lua` writes popup and submenu lists into a unique
temporary directory. Tests must not write or remove the live
`$TMPDIR/sketchybar_popup_list` or `$TMPDIR/sketchybar_submenu_list`: missing
authoritative lists make the helpers fall back to retired hard-coded entries
such as `yaze.recent_roms` and `emacs.recent_org`, producing repeated
`Item not found` warnings. Reload Barista to regenerate both live lists if they
are ever removed.

### 8. Apple Menu Reload Stability
**Current path**: `modules/menu.lua` + `modules/apple_menu_enhanced.lua` + `helpers/popup_anchor.c` (native) / `plugins/popup_anchor.sh` (fallback)
- The Apple menu hover now highlights the anchor, but click still opens the popup.
- The hover highlight now clears itself after the short bar timer, so anchors do not stay lit while you linger.
- `apple_menu` still uses the popup-anchor helper for hover/click handling, but it no longer sets `POPUP_OPEN_ON_ENTER=1` and normal runtime does not subscribe it to `mouse.exited.global`.
- SketchyBar still rejects `env` as an item subdomain; when that regresses, reloads can leave the bar temporarily empty while the config pass is poisoned.
- Barista now also stops its widget/runtime daemons before `begin_config`, so reloads do not keep spamming updates into items that were just removed.
- The active fix is:
  - `script = ".../popup_anchor"`
  - no `POPUP_OPEN_ON_ENTER=1` on `apple_menu`
  - no `env = { ... }` table on the `apple_menu` item

### 9. Volume Popup Click Path
**Current path**: generated `ui.toggle_then_refresh_async("volume", ...)` click script + `bin/volume_popup_helper` (compiled) / `plugins/volume.sh` (portable fallback)
- Volume no longer queries popup state before opening.
- Click toggles the popup immediately, then refreshes popup rows in the background.
- Compiled setups read volume/mute/output state through CoreAudio, reuse bounded
  `cache/runtime_context/{media,outputs}.tsv` snapshots, and update the ten
  mutable items in one bounded SketchyBar request/reply.
- Stable USB or hardware-controlled outputs with no software volume/mute
  properties show `HW` and `Volume: Hardware controlled`, keep output/media
  rows available, and hide mute. Switching back to a controllable output
  explicitly redraws the mute action.
- Initial state and `volume_change` events prefer the same helper. The delayed
  startup refresh runs after subscription so reload does not leave a
  hardware-controlled output labeled `Muted`.
- The native helper waits for SketchyBar's reply; transport, timeout, semantic
  `[!]`, transient CoreAudio read, and unstable-device failures run the shell
  refresh instead. Mere property absence on a stable, live device does not.
  From the repo, test that fallback once with
  `BARISTA_VOLUME_NATIVE_DISABLE=1 build/bin/volume_popup_helper popup_refresh || plugins/volume.sh popup_refresh`.
  To force live clicks onto the shell path, run
  `launchctl setenv BARISTA_VOLUME_NATIVE_DISABLE 1` and reload Barista; undo
  with `launchctl unsetenv BARISTA_VOLUME_NATIVE_DISABLE` plus another reload.
- Invalid, oversized, non-UTF-8, symlinked, or non-regular cache files are
  ignored independently by the native helper: bad media becomes empty state,
  bad outputs hide route rows, and neither rejected file is handed back to the
  shell path.
- `plugins/volume_click.sh` is only a compatibility wrapper for the same toggle-then-refresh behavior; the live item uses the generated direct click script.
- The popup now surfaces output route, now-playing state, and transport controls through `scripts/media_control.sh`, plus mute and Sound settings.
- `scripts/media_control.sh` prefers the shared `scripts/runtime_context.sh` cache for player state and output routes, so the popup and output switch rows reuse the same runtime snapshot.
- If `SwitchAudioSource` is not installed, the refresh skips output-route
  discovery and leaves those action rows hidden instead of regenerating an
  unusable empty route cache on every click. Now Playing still refreshes.
- Long now-playing labels are truncated before they hit SketchyBar on both
  native and shell paths, keeping the popup width predictable. The native path
  preserves composed Unicode and passes labels as direct protocol arguments,
  not shell text.
- This keeps the volume anchor aligned with the other right-side widgets that
  toggle immediately and refresh detail state asynchronously; it adds no new
  widget or polling timer.

### 10. Front App Context Fallback
**Current path**: `plugins/front_app.sh` + `scripts/front_app_context.sh`
- `front_app` no longer relies only on `yabai --windows --window` for popup state/location.
- The helper prefers the shared `scripts/runtime_context.sh` cache when available, then falls back to direct discovery.
- The shared helper first tries the focused window, then falls back to the best matching window for the current app on the active space/display.
- The compiled runtime helper now also prefers the focused yabai window's app name before falling back to `NSWorkspace`, so live Ghostty/managed-window state no longer degrades to `No managed window` when AppKit focus naming diverges from yabai.
- If no managed window matches, `front_app` now still shows the current space/display and labels the state as `No managed window` instead of falling back to `Space ? · Display ?`.
- If current-space discovery misses but the selected app window is still known, the helper now backfills raw `space_index` / `display_index` from that window instead of leaving those fields blank.
- The front-app state label now distinguishes `Floating · Float Space` from `Floating · Managed Space`, so a per-window float inside a tiled space is not conflated with a true float-space workflow.
- `scripts/yabai_control.sh` now applies the same rule on window moves: when the destination space is `float`, the moved window is normalized to floating after the move instead of landing in a mismatched tiled state.
- Cross-display window moves now adopt the visible destination space mode in both directions. A floating window moved onto a managed display is re-tiled, and a tiled window moved onto a float display is floated.
- The `Toggle Topmost` action now maps to yabai's current window `sub-layer` control (`above` / `auto`) instead of the removed `--toggle topmost` flag, so the popup and skhd shortcut no longer emit runtime errors on yabai 7.x.
- The `front_app` popup now updates its float/fullscreen/topmost row labels from the current window state, so the row explains the next action instead of always saying `Toggle`.
- The fully enabled `front_app` root now shows 13 rows instead of 18. `Quit App`, `Float Window`, `Adopt Current Space Mode`, and `Fullscreen` stay direct. The existing click-only `front_app.more` child is now labeled `More Actions` and grows from 12 rows to 17 by adding `Hide App`, `Force Quit`, `Sticky`, `Topmost`, and `Center` beside the `Utility`, `Focus`, `Presentation`, and `Tile Here` presets plus display/space moves.
- `Send to Float Space` remains in the child. Root toggles still reset the child first, and child actions still close both popup levels after running. Disabled/no-Yabai layouts keep Hide and Force Quit with the other app actions on the root and omit the child.
- The Control Center popup keeps persistent app-default controls out of the smaller `front_app` popup. In enabled setups, its click-only `More Layout Controls` child contains `Default App: Float`, `Default App: Tile`, and `Unset App Default`; they call `scripts/yabai_control.sh app-default-current ...`, persist the choice in `state.json` under `window_defaults.apps`, and install/remove a labeled live yabai rule (`barista-default-*`) when yabai is running.
- `app-default-current` uses the same front-app context fallback when yabai has
  no focused managed window, so unmanaged/frontmost utility apps can still be
  saved as app defaults.

### 11. Runtime Context Helper
**Current path**: `main.lua` + `modules/runtime_daemon.lua` + `scripts/runtime_context.sh` + `bin/runtime_context_helper`
- Barista now uses `runtime_context_helper` for the front-app / focused-space cache path when the helper is built.
- `runtime_context.sh` still owns media/output cache refresh and supervises the helper-side front-app daemon.
- Media discovery uses one strict, versioned AppleScript snapshot with a bounded legacy fallback. The daemon checks it every tick while playing, every two ticks for a paused/running player, and every three ticks while idle; `refresh media` and media actions remain immediate.
- `media.tsv` and `outputs.tsv` are atomically replaced only when their bytes change in every runtime mode. When the native helper is active, `front_app.tsv` gets the same stable-identity behavior; the portable front-app fallback still refreshes its cache every base tick. Stable inode/mtime values are therefore expected during unchanged playback/output state and during unchanged app state on the native path. The native front-app publisher uses a bounded regular-file comparison, repairs file/dangling symlinks, FIFOs, and corrupt snapshots, and rejects directory targets including symlinks to them.
- Audio probes are timeout-bounded, failed current-output discovery leaves route rows unselected, and only the four routes the popup can display are cached.
- A runtime launched with `runtime_backend=lua` propagates `BARISTA_LUA_ONLY=1`, preventing a leftover `bin/runtime_context_helper` from being used by the daemon.
- The shared cache under `cache/runtime_context/` is the current source for front-app state, focused-space fast-path refreshes, media state, and audio output switching.
- `runtime_daemon.stop_runtime_context_daemon()` now kills the whole runtime-context family on restart, including stale shell refresh wrappers and `runtime_context_helper daemon`, `refresh-front-app`, or `fresh-front-app` children, so reloads do not accumulate orphaned helper/query processes.
- `runtime_context.sh daemon` now backgrounds the helper binary directly instead of backgrounding a shell function, so the live runtime settles to one shell supervisor plus one helper daemon instead of leaving a redundant nested shell layer.
- `runtime_daemon.ensure_runtime_context_daemon()` now writes a per-launch start token and the final launcher shell only `exec`s when its token is still current, so overlapping config passes cannot both spawn the daemon family.
- The native helper no longer launches its focused-window/spaces pair on every
  one-second base tick. App activation, active-space, and wake notifications
  schedule a 50 ms debounced refresh on the helper thread, while a five-second
  safety refresh covers missed events and external same-app window changes.
  Front-app clicks still toggle immediately, then consume one fresh returned
  snapshot in the background; portable/Lua-only setups retain their base-tick
  producer and cannot reactivate a leftover compiled helper on click.
- `front_app.sh` applies its anchor plus available mutable popup rows in one
  animated SketchyBar request. Yabai-enabled layouts include all eight targets;
  disabled-yabai or unavailable-yabai layouts omit unavailable action targets
  and keep the four-item base batch to one request. An animated-request failure
  retries the identical batch once without animation while retaining the
  portable shell path and configured SketchyBar binary.

### 12. Reload Serialization
**Current path**: `plugins/reload_sketchybar.sh`
- `reload_sketchybar.sh` now uses a short-lived lock directory under `TMPDIR` to serialize overlapping reload requests.
- Callers that arrive while another reload is already in flight now wait for that reload to finish and exit early if `front_app` is already live, instead of issuing a second LaunchAgent stop/bootstrap cycle.
- Reload completion now also waits for `space.1`; if spaces are missing after the core item is live, it runs `plugins/refresh_spaces.sh` before returning.
- The reload helper does not schedule a second detached spaces repair; normal startup owns the native delayed refresh, while the synchronous missing-space check remains the recovery path.
- This prevents rapid repeat invocations from leaving SketchyBar running without its runtime daemons after competing launchctl restarts.
- skhd reload shortcuts now route through `plugins/reload_sketchybar.sh` instead of raw `sketchybar --reload`.

### 13. Shortcut Doctor
**Current path**: `scripts/yabai_control.sh doctor`
- The doctor reports the active skhd config path, the generated Barista shortcuts path, loaded skhd files, generated-shortcut include health, duplicate bindings, recent skhd log warnings, and a minimal yabai space-focus check.
- The doctor also prints a compact shortcut summary: active/disabled binding count, duplicate count, raw yabai command count, and missing command target count.
- Use `scripts/yabai_control.sh shortcuts` for the full loaded skhd inventory, grouped by source file. Use `--json` when another tool needs the same data.
- Use `scripts/yabai_control.sh rules-audit` to compare active yabai rules and live windows against Barista's unmanaged utility policy: `manage=off sub-layer=normal`, with topmost treated as an explicit/manual state. Use `--json` for a machine-readable finding list.
- `doctor --fix` keeps the existing repair behavior for missing generated shortcut includes and skhd restart/reload paths.

### 14. Control Panel Launch
**Current path**: `bin/open_control_panel.sh`
- SketchyBar's Barista Settings menu row launches the native `Barista.app` through LaunchServices (`open -na ... --args`) instead of directly executing the bundle binary.
- Direct bundle execution can create the window and then exit immediately; LaunchServices keeps the app registered and the settings panel visible.

### 15. Process Diagnostics
**Current path**: `scripts/process_manager.sh`
- `process_manager.sh load` prints a compact current load snapshot: system load, top process, Barista aggregate CPU/memory, and runaway count/details.
- `process_manager.sh barista` prints the live SketchyBar/yabai/skhd/widget/runtime-context/space-script process family.
- `process_manager.sh runaways` flags high-CPU or duplicated Barista space plugin scripts.
- `process_manager.sh cleanup-runaways` is a dry run unless `--yes` is passed, so diagnostics stay non-destructive by default.

## Native Widget Paths

Barista resolves compiled helpers automatically from `build/bin/` and then
`bin/`. Do not replace widget scripts manually in `main.lua`; the shell wrappers
remain the event, hover, and portable fallback boundary.

### Clock

`clock_widget` uses the native time APIs for the routine clock label. Lua-only
or helper-missing setups retain `plugins/clock.sh` without configuration edits.

### System Info: Routine vs. Popup

`helpers/system_info_widget.c` builds two independently addressable binaries:

- `system_info_widget` is the established daemon-disabled routine entrypoint. It
  gathers compact CPU/memory state and updates only the `system_info` anchor;
  `widget_manager daemon` owns that cadence on default compiled setups.
- `system_info_popup_helper` is the click-only `popup_refresh` entrypoint. Its
  separate name is an upgrade guard: an older routine-only binary is never
  treated as if it implements the new popup action.

`modules/items_right.lua` derives the dynamic popup topology once and passes the
exact enabled subset of `cpu,mem,disk,net,swap,uptime,procs`, or `none` when no
dynamic row exists. The native and shell parsers both reject malformed,
duplicate, or unknown row names before issuing partial updates. Activity Monitor
and System Settings stay outside that metric allowlist. Top CPU already opens
Activity Monitor, so the separate Activity Monitor row is omitted while Top CPU
is enabled and restored when Top CPU is disabled. System Settings remains direct.
Setting `system_info_items.actions=false` removes both static launchers and makes
Top CPU informational without removing it from the dynamic helper allowlist.

Click behavior is deliberately split:

1. SketchyBar toggles `popup.system_info` immediately.
2. The click script starts `system_info_popup_helper popup_refresh` in the
   background.
3. The helper collects only the enabled rows, sanitizes bounded label/icon
   tokens, and submits one batched, bounded SketchyBar Mach payload.
4. If the popup helper is absent or its invocation/IPC fails, the command runs
   `plugins/system_info.sh popup_refresh`. The explicit popup action does not
   retry `system_info_widget`, so the fallback cannot recurse.

Lua-only layouts and layouts without a resolved routine helper pass
`BARISTA_SYSTEM_INFO_NATIVE_DISABLE=1` to the wrapper. This prevents a stale
`bin/system_info_widget` left by an earlier compiled setup from crossing the
script-only boundary; the shell path still updates the compact anchor and the
same exact popup-row subset.

### System Info Probe Model

The native helper combines direct APIs with a small set of deliberately bounded
child probes; it is not subprocess-free:

- CPU, swap, uptime, active+wired+compressed memory, Wi-Fi-interface discovery,
  and interface addresses use native APIs such as `getloadavg`,
  `sysctlbyname`, Mach host statistics, SystemConfiguration, and `getifaddrs`.
- Disk uses bounded `/bin/df -h` against `/System/Volumes/Data`, falling back to
  `/` only when the Data volume is unavailable.
- Network selects the configured or default-route interface through bounded
  `/sbin/route`, reads addresses with `getifaddrs`, and invokes
  `/usr/sbin/networksetup` only for an optional SSID on the selected Wi-Fi path.
- The optional top-process row reads only the first bounded line from the
  system-wide `/bin/ps -Ar -o pcpu=,pid=,ucomm=` ranking. Native PID lookup
  restores the executable basename where allowed; the dependable accounting
  name remains the permission/race fallback without widening the popup.

Every child uses an absolute executable path, capped output, a deadline, and
TERM/forced-kill cleanup. Concurrent probes use close-on-exec-default spawn
isolation so one child cannot keep another probe pipe alive. Probe failure
yields a safe placeholder for that row; payload, parser, native-disable, or
Mach IPC failure returns nonzero so the shell fallback can take over where
applicable.

### Build and Verify

Use the repository CMake wiring rather than hand-installing or editing widget
scripts:

```bash
cmake -B build -S .
cmake --build build --target \
  system_info_widget system_info_popup_helper sync_binaries

lua tests/run_tests.lua tests/test_items.lua
bash tests/test_system_info_memory.sh
bash tests/test_system_info_widget.sh   # Darwin native contract
./scripts/barista-verify.sh
```

For a supported live restart after verification, use
`./plugins/reload_sketchybar.sh`, not a raw reload command. The final discovery
profile measured the full helper at 25.376 ms median / 25.978 ms p95 and 20
exact live updates at 25.463 / 26.533 ms. A later controlled profile found the
exact background refresh dispatch at only 5.272 / 11.626 ms median/p95, direct
popup open at 79.627 / 85.288 ms, and the full configured launcher at 79.883 /
87.088 ms. The 110.029 / 137.852 ms label observer includes repeated open-popup
query latency; the earlier 43.657 / 49.583 ms "shell launch" attribution was
confounded. A randomized five-versus-seven-row root A/B produced only a noisy
-0.446 ms paired median, so the tested nested-details prototype was rejected.
Keep the popup flat and do not add a C click server to chase the roughly 5 ms
client floor; SketchyBar/WindowServer materialization dominates. Full methodology
is in `docs/PERFORMANCE_AUDIT.md`. Treat all figures as one-machine evidence.
