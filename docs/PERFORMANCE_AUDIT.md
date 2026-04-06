# Barista Performance & Safety Audit

**Date:** 2026-04-05
**Status:** Active runtime app-model path verified
**Scope:** `barista/src`, `barista/helpers`, `barista/plugins`

## Executive Summary
Following the initial audit, the active runtime path was tightened again in April 2026. The number of process forks on hot paths is still materially lower than the original shell-heavy bar, but the more important change is architectural: routine updates now stay on long-lived helpers, while expensive detail collection and space visuals run on explicit event paths.

## Resolved / Mitigated "Hot Spots"

### 0. Widget Daemon + Routine vs. Detail Paths (Verified)
*   **Files:** `main.lua`, `modules/items_right.lua`, `modules/runtime_daemon.lua`, `plugins/system_info.sh`, `plugins/battery.sh`, `helpers/widget_manager.c`
*   **Update:**
    - `clock`, `system_info`, and `battery` can be daemon-managed through `widget_manager daemon`
    - expensive popup rows refresh only when the popup is opened
    - `modes.widget_daemon` now controls whether the daemon is `auto`, `enabled`, or `disabled`
    - reload now force-restarts the daemon so rebuilt helpers replace the running process instead of leaving stale code resident
*   **Result:** steady-state right-side updates no longer depend on per-item timer scripts when the compiled runtime is available.

### 0b. Runtime Context Cache + Shared Front-App / Media Boundary (Verified)
*   **Files:** `main.lua`, `modules/runtime_daemon.lua`, `scripts/runtime_context.sh`, `scripts/front_app_context.sh`, `scripts/media_control.sh`, `plugins/volume.sh`
*   **Update:**
    - `runtime_context.sh` now prefers compiled `runtime_context_helper` commands for front-app / focused-space cache refresh and reads
    - the shell daemon still owns media/output cache refresh, but it starts and supervises a helper-side front-app daemon when the compiled helper is present
    - `front_app_context.sh` prefers the cached front-app state before falling back to direct yabai/System Events discovery
    - `media_control.sh` prefers cached player/output state before falling back to direct AppleScript / `SwitchAudioSource`
    - the volume popup now exposes cached output routes and switches outputs by cached index instead of rediscovering devices on every popup refresh
    - shell smoke tests now cover the helper delegation path, front-app fallback behavior, daemon cache warming, and cached output switching
*   **Result:** the hottest front-app / spaces path no longer depends on the shell implementation of `runtime_context.sh`, while audio continues to share the same cache surface.

### 1. Network & System Info (Mitigated)
*   **File:** `helpers/system_info_widget.c`
*   **Update:** Batched 5 separate `system()` calls into a single `sketchybar` invocation.
*   **Result:** Reduced 5 fork+exec cycles to 1 per update interval. Perl-based timeouts remain as safety.

### 2. Space Management (Verified Active Path)
*   **Files:** `plugins/refresh_spaces.sh`, `plugins/simple_spaces.sh`, `plugins/space.sh`, `plugins/space_visuals.sh`, `main.lua`
*   **Update:**
    - topology rebuild stays in `refresh_spaces.sh` + `simple_spaces.sh`
    - real `space_changed` yabai signals now route through `refresh_spaces.sh`, so active-space updates reuse the same cache/lock path as topology refreshes
    - per-space `space_change` and `space_mode_refresh` scripts were removed from the active items
    - dead per-space popup menu rows were removed from the rebuild path
    - a hidden `space_runtime` item now owns event-driven visual refresh
    - `refresh_spaces.sh` runs one deterministic visual pass immediately after rebuild so startup ordering is stable
    - active app glyph lookup now reuses a cache instead of calling `app_icon.sh` for the same app every refresh
    - the app-glyph cache is versioned so alias corrections invalidate stale cached space icons automatically
    - topology-presence checks now use one SketchyBar item snapshot instead of per-space `--query` loops
    - `simple_spaces.sh` now caches non-visual space/creator property signatures and skips its batched `--set` pass when click targets and heights did not change
    - when topology changes but the `space.*` item set stays the same, `simple_spaces.sh` now reorders and updates the existing space items in place instead of doing a full remove/re-add cycle
    - when topology changes add or remove specific spaces, `simple_spaces.sh` now removes stale `space.*` items and adds missing ones directly instead of resetting the whole space stack
    - creator-only topology changes now rebuild only `space_creator*` items instead of tearing down all `space.*` items
    - creator items no longer query and bind themselves to the current visible space, so the add-space affordance remains display-visible and avoids extra topology churn
    - startup no longer blocks waiting for `front_app`; the full rebuild path now falls back to the next available anchor immediately and lets the existing async reorder path repair final placement later
    - the initial spaces rebuild and `space_runtime` subscription now use a dedicated shorter post-config delay instead of inheriting the broader 1.0s bar delay, so the spaces stack settles earlier after reload
    - the enhanced Apple-menu model is now prepared before `begin_config`, so tool discovery and menu section sorting no longer happen inside the cleared-bar window
    - anchor selection now reuses the existing bar-item snapshot instead of issuing extra `sketchybar --query <item>` calls during full-rebuild preparation
    - full-rebuild preparation now reuses one state-file read for space config flags, one bar snapshot for bar height plus item presence, and one sorted jq pass over `RAW_SPACES_DATA` for topology + visible-space parsing
    - creator placement now reuses the already-resolved active display instead of issuing a second `yabai --displays --display` query
    - full-rebuild preparation now reuses one display-state snapshot for both active-display and display-count lookups
    - diff-path prep now reads `.spaces_signatures` once into cached shell variables instead of rescanning it with multiple `awk` processes
    - full-rebuild prep now skips diff-signature computation entirely when the current bar snapshot has no `space.*` items, avoiding work that cannot produce an incremental update on cold reloads
    - full-rebuild prep now bulk-loads cached space icons once per run instead of probing one cache file per space during the item-build loop
    - `space_visuals.sh` now coalesces overlapping runs and cools down `front_app_switched` updates immediately after authoritative refreshes
    - `front_app_switched` now has a focused-space fast path: `space_visuals.sh` delegates current-space resolution to `scripts/front_app_context.sh`, updates only the focused visible space, and skips the full `yabai --windows` snapshot
    - `space_visuals.sh` now caches the `space.*` item lookup under `cache/space_visuals/space_items` and reuses it on the focused-space fast path, avoiding a full `sketchybar --query bar` on repeated `front_app_switched` visual refreshes
    - `refresh_spaces.sh` now passes the already-fetched spaces payload into `space_visuals.sh`, so authoritative visual refreshes reuse the same `yabai query --spaces` result instead of querying spaces twice
    - `space_active_refresh` now uses the same focused-space fast path as `front_app_switched`, so an active-space-only refresh no longer falls back to the full spaces + windows snapshot path when the focused-space helper already has the answer
    - pure active-space refreshes no longer emit a redundant `space_mode_refresh`; the existing `space_change` event is enough for the active-path listeners and cuts orchestration overhead on space switches
    - authoritative visual refreshes now resolve app state with scoped `yabai query --windows --space <index>` calls for visible spaces instead of taking one global window snapshot for every space
    - the active spaces scripts (`refresh_spaces.sh`, `simple_spaces.sh`, `space_visuals.sh`) now all accept injected `BARISTA_*_BIN` overrides so shell smoke tests exercise the same runtime boundary deterministically
    - startup now schedules one delayed direct `space_visuals.sh` pass after the runtime subscriptions are back up, so the spaces strip settles to the real focused space after reload instead of relying only on the first topology-driven pass or the event/subscription race
*   **Result:**
    - per-space handlers are now hover-only
    - full rebuilds create fewer items and avoid unused popup rows
    - startup reloads produce both topology and visual refresh timings
    - the `space_visual_refresh` event can be triggered independently for focused visual updates.

### 2b. Control-Center Popup Cleanup (Verified Active Path)
*   **Files:** `modules/integrations/control_center.lua`, `plugins/control_center.sh`
*   **Update:**
    - removed service-health, workspace dirtiness, and utility rows from the popup
    - stopped the live updater from computing dirty-repo and service-row state that no longer has a visible consumer
*   **Result:** the control-center runtime now matches the simplified popup and avoids unnecessary work on each refresh.

### 3. Popup & Submenu Execution (Resolved)
*   **File:** `helpers/popup_hover.c`
*   **Update:** Replaced `system()` with `execlp()`.
*   **Result:** Eliminates shell parsing and one fork per hover event. Subsecond latency on popups.

### 4. Yabai Query merging (Resolved)
*   **File:** `plugins/refresh_spaces.sh`
*   **Update:** Merged 3 separate `yabai` queries into 1.
*   **Result:** Reduced IPC round-trips and process forks by 66%.

## Ongoing Lua Integration Improvements
The Lua layer now uses a modular architecture (decomposed from `main.lua`) to improve initialization performance and testability.

*   **File:** `modules/shell_utils.lua`
*   - Introduced `command_available()` and `check_service()` to standardize and optimize external dependency checks.
*   - Lazy-loading of `sketchybar` module to ensure testability and faster startup.

### 5. Runtime Instrumentation (Verified)
*   **Files:** `sketchybarrc`, `main.lua`, `bin/barista-stats.sh`, `plugins/refresh_spaces.sh`, `plugins/space_visuals.sh`
*   **Update:**
    - reload timing is emitted before `sbar.event_loop()` blocks
    - config-build timing is emitted separately for the `begin_config` to `end_config` window
    - config-build timing is now also split into menu render, left layout, right layout, and registry phases
    - left and right layout timing are now further split into layout build vs. SketchyBar apply, so the runtime can distinguish Lua-side layout construction from item registration cost
    - the left-side Oracle and control-center builders now reuse one shared model/status snapshot per config pass instead of rebuilding the same runtime state twice
    - left-layout timing is now also broken out by subsection (`front_app`, `triforce`, `spaces`, `control_center`, `group`) so the remaining build-side cost can be targeted precisely
    - config-build and left-layout subsection timing now use an in-process profiling clock instead of spawning a timestamp subprocess for every probe; total `reload_time` remains wall-clock
    - `simple_spaces.sh` now derives active display and display count from the existing spaces payload in the normal path, avoiding a second `yabai --displays` query unless the focused display cannot be inferred
    - `space_topology_refresh` now records pure `simple_spaces.sh` topology time from the child metrics file instead of the entire `refresh_spaces.sh` runtime; the remaining orchestration is tracked separately as `space_refresh_overhead`
    - topology metrics temp files are now created lazily and live in `TMPDIR` instead of cluttering the Barista config/repo directory
    - `refresh_spaces.sh` now caches the last applied external-bar height and skips re-running `yabai -m config external_bar ...` on unchanged active-only refreshes
    - `runtime_daemon.stop_runtime_context_daemon()` now clears the whole runtime-context family on restart, including stale helper daemon and refresh children, so live focused-space probes no longer inherit orphaned runtime/query processes across reloads
    - `runtime_context.sh daemon` now launches `runtime_context_helper daemon` directly instead of backgrounding a shell function, removing the redundant nested shell layer from the live runtime path
    - topology and visual refresh durations are logged separately
    - topology refresh events now carry explicit strategy/counter metadata (`strategy`, `added`, `removed`, `updated`, `spaces`)
    - full-rebuild topology events now also carry `prepare_ms` and `apply_ms`, so `barista-stats.sh show` separates script-side preparation from the SketchyBar batch apply cost
    - the live stats now also split `full_rebuild` preparation into `discovery`, `build`, and `decision` phases so the remaining shell-side cost can be targeted more precisely
    - `barista-stats.sh` now writes JSONL and migrates legacy pipe-delimited logs aside
    - `barista-stats.sh show` summarizes the live runtime path and breaks topology timings out by strategy so incremental reorder/add-remove paths are measured separately from full rebuilds
*   **Result:** reload time, topology rebuild time, incremental topology update time, and visual refresh time are now measurable from the installed runtime.

## Remaining Considerations
1.  **Window snapshot cost:** `space_visuals.sh` now uses one full window snapshot per pass, but that yabai query is still part of the visual-refresh hot path.
2.  **Clock daemon coverage:** the current daemon path is verified live, but there is still no dedicated test coverage around `main.lua` startup instrumentation.
3.  **Topology rebuild cost:** `simple_spaces.sh` is materially cheaper after removing dead popup rows, but full rebuild remains the dominant startup cost.
4.  **Async I/O:** the current architecture is event-driven enough for daily use, but long-term migration to a fully async runtime remains the cleaner end state.
5.  **Mixed runtime boundary:** front-app context is now helper-backed, but media/output state still depends on the shell runtime and AppleScript / `SwitchAudioSource`.

## Shell Script Optimization Summary
- **AWK Variable Naming**: Standardized to avoid collisions.
- **Binary Paths**: Fixed to `/opt/homebrew/bin/sketchybar` (or resolved via `paths.lua`).
- **Batching**: System-wide adoption of array-based argument building for `sketchybar` calls.
