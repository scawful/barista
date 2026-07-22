# Barista Performance & Safety Audit

**Date:** 2026-07-16
**Status:** Active runtime app-model path verified
**Scope:** `main.lua`, `modules/`, `helpers/`, `plugins/`, `scripts/`

## Executive Summary
Following the initial audit, the active runtime path was tightened through July
2026. The number of process forks on hot paths is still materially lower than
the original shell-heavy bar, but the more important change is architectural:
routine updates now stay on long-lived helpers, while expensive detail
collection, task snapshots, and space visuals run on explicit event paths.

## Resolved / Mitigated "Hot Spots"

### 0. Widget Daemon + Routine vs. Detail Paths (Verified)
*   **Files:** `main.lua`, `modules/items_right.lua`, `modules/runtime_daemon.lua`, `plugins/system_info.sh`, `plugins/battery.sh`, `helpers/widget_manager.c`
*   **Update:**
    - `clock`, `system_info`, and `battery` can be daemon-managed through `widget_manager daemon`
    - the compiled daemon updates the clock only when the minute changes, system info every 10 seconds, and battery every 120 seconds
    - its scheduler sleeps for one second between due checks instead of waking every 100 ms
    - expensive popup rows refresh only when the popup is opened
    - `modes.widget_daemon` now controls whether the daemon is `auto`, `enabled`, or `disabled`
    - reload now force-restarts the daemon so rebuilt helpers replace the running process instead of leaving stale code resident
*   **Result:** steady-state right-side updates no longer depend on per-item timer scripts when the compiled runtime is available.

### 0a. Calendar + Task Pulse Event Path (Verified)
*   **Files:** `modules/items_right.lua`, `plugins/calendar.sh`, `plugins/task_pulse.sh`, `scripts/task_snapshot.py`, `scripts/task_focus.sh`, `scripts/task_capture.sh`, `main.lua`
*   **Update:**
    - the calendar popup header no longer has a periodic `update_freq`; clock clicks and `⌘⌥D` open immediately and refresh the popup asynchronously
    - `plugins/calendar.sh` applies every calendar/task row in one batched SketchyBar invocation
    - one optional next-meeting row reads only a configured local TSV cache; Barista performs no auth, sync, or network calls
    - optional Task Pulse has no polling timer and is not created unless both `widgets.task_focus=true` and a task source are configured
    - its closed anchor renders only an open-count label; the popup owns bounded task detail and one local 25-minute focus-session toggle
    - focus-session state is deadline-derived from a private ignored cache file, with no resident timer process or extra bar widget
    - Task Pulse refresh runs on click, `task_state_changed`, or `system_woke`
    - task capture emits `task_state_changed` after a successful syshelp write; external task tools can trigger the same event explicitly
    - task source/provider values are passed through quoted environment fields; committed defaults contain no task paths
*   **Result:** closed task/calendar surfaces add no steady-state task parsing or popup-update work, while configured users still get immediate refresh after interaction or task mutation.

### 0b. Runtime Context Cache + Shared Front-App / Media Boundary (Verified)
*   **Files:** `main.lua`, `modules/runtime_daemon.lua`, `scripts/runtime_context.sh`, `scripts/front_app_context.sh`, `scripts/media_control.sh`, `plugins/volume.sh`
*   **Update:**
    - `runtime_context.sh` now prefers compiled `runtime_context_helper` commands for front-app / focused-space cache refresh and reads
    - the shell daemon still owns media/output cache refresh, but it starts and supervises a helper-side front-app daemon when the compiled helper is present
    - `front_app_context.sh` prefers the cached front-app state before falling back to direct yabai/System Events discovery
    - `media_control.sh` prefers cached player/output state before falling back to direct AppleScript / `SwitchAudioSource`
    - the volume popup now exposes cached output routes and switches outputs by cached index instead of rediscovering devices on every popup refresh
    - when `SwitchAudioSource` is unavailable, the volume popup skips output-route discovery entirely, keeps the unusable route rows hidden, and still reads cached Now Playing state; an interleaved local profile reduced median refresh work from 292 ms to 238 ms (19%)
    - the compiled helper drains a per-refresh autorelease pool on every daemon iteration and explicitly closes task pipe handles, bounding descriptor use and reducing Foundation task/data retention across long-running sessions
    - shell smoke tests now cover the helper delegation path, front-app fallback behavior, daemon cache warming, and cached output switching
*   **Result:** the hottest front-app / spaces path no longer depends on the shell implementation of `runtime_context.sh`, while audio continues to share the same cache surface.

### 0c. Native Volume State and Popup Detail Path (Verified)
*   **Files:** `helpers/volume_popup_helper.m`, `modules/items_right.lua`, `plugins/volume.sh`, `tests/test_volume_popup_helper.sh`, `tests/test_volume_plugin.sh`, `tests/test_items.lua`
*   **Update:**
    - the anchor still toggles immediately; compiled setups refresh the ten mutable volume/popup items through one Objective-C helper used by startup, volume-change, and click-detail paths
    - volume and mute state come from CoreAudio, including virtual-main, main-element, preferred-stereo, and bounded discovered-channel fallbacks; the real CoreAudio output-device name is used when no cached route name exists
    - a stable, live default device with absent software volume or mute properties is distinct from a property read error: hardware-controlled outputs stay native, render `HW` / `Volume: Hardware controlled`, and hide unavailable mute; a later controllable device explicitly restores the mute row with `drawing=on`
    - device-alive and unchanged-default checks fence disconnect races, while property-present read failures and malformed channel topology retry once and then fail closed instead of publishing partial channel state
    - media and output rows reuse the existing runtime TSV caches through bounded regular-file reads (64 KiB file / 4 KiB line caps, strict UTF-8, no symlinks or FIFOs); invalid media data becomes an empty media snapshot, invalid output data hides route rows, and neither falls through to an unbounded shell read
    - all ten item updates use one bounded NUL-delimited Mach request and wait for SketchyBar's bounded reply, so transport failures and `[!]` semantic errors select the shell fallback
    - cache labels remain individual protocol arguments, preserving quotes and composed Unicode without shell evaluation; payload, token, argument, and label lengths are capped
    - `SwitchAudioSource` capability detection checks an explicit override, inherited `PATH`, and standard Homebrew prefixes; absent capability keeps all four route actions hidden
    - initial and `volume_change` events delegate through the same helper when available; the post-config subscription performs one ordered refresh instead of racing a separate synthetic event
    - Lua-only/helper-missing, `BARISTA_VOLUME_NATIVE_DISABLE=1`, transient CoreAudio/device instability, and IPC-failure paths retain `plugins/volume.sh`; absent controls on a stable device no longer force that fallback
*   **Result:** the original 20-pair alternating live sample reduced median detail-refresh latency from 281.08 ms to 49.32 ms (82%, 5.70x) and p95 from 298.94 ms to 55.61 ms (81%, 5.38x). On the current hardware-controlled M4 output, 20 randomized before/after pairs changed helper exit `3` plus shell fallback into native exit `0`, reducing median refresh latency from 429.62 ms to 103.83 ms (75.8%, 4.14x) and p95 from 1131.56 ms to 247.49 ms (78.1%). System load averaged above 70 during the latter run, so exit behavior and direction are stronger evidence than the absolute latency. No widget or polling timer was added.

### 0d. Adaptive Media Cache Producer (Verified)
*   **Files:** `scripts/runtime_context.sh`, `modules/runtime_daemon.lua`, `main.lua`
*   **Update:**
    - one versioned AppleScript snapshot now resolves Spotify/Music lifecycle, state, track, and artist in a single bounded call; malformed or timed-out responses fail closed into the legacy probes
    - the media probe stays at one-second cadence while playing, backs off to two ticks for a paused/running player, and three ticks when no supported player is running
    - media and output candidates are compared with the actual regular cache file before atomic publication, so unchanged snapshots retain their inode and modification time; missing targets, symlinks to files, and FIFOs are replaced rather than trusted, while directory targets (including symlinks to them) are rejected
    - output topology remains checked every base tick for bounded route staleness, but unchanged rows are no longer rewritten; current-route failure leaves all rows unselected instead of fabricating the first route as current
    - media AppleScript and `SwitchAudioSource` work is timeout-bounded, TSV fields and route counts are capped, and one current-output read is shared when media/output work is due together; the portable front-app/TCC path keeps its existing behavior
    - explicit Lua-only launches now pass `BARISTA_LUA_ONLY=1` into the runtime-context daemon so a leftover compiled helper cannot silently reactivate on a restricted/work setup
*   **Result:** the idle/no-player path drops from two AppleScript launches every second to one combined launch every three seconds, while explicit media actions still refresh immediately and the four-row popup/cache contract is unchanged. Before reload, unchanged live media/output caches were each replaced 10 times in 10.299 seconds; after reload, each held one inode/mtime across 10 samples spanning 9.45 seconds. A directional isolated sample reduced median explicit no-player refresh time from 78.543 ms to 64.710 ms (17.6%); system-load drift makes the live churn/call-count result the stronger signal.

### 0e. Change-Driven Native Front-App Publication (Verified)
*   **Files:** `helpers/runtime_context_helper.m`, `tests/test_runtime_context_helper_publication.sh`, `tests/test_runtime_context_daemon_exec.sh`, `scripts/check_scripts.sh`
*   **Update:**
    - the native helper compares the deterministic front-app TSV against an existing regular file before atomic publication, preserving inode and modification time when the bytes are identical
    - comparison uses a no-follow, nonblocking descriptor, exact-size validation, a fixed 4 KiB buffer, binary comparison, and an EOF check; symlinks, FIFOs, directories, NUL suffixes, and oversized prefix-equal files cannot be accepted as unchanged
    - missing, changed, corrupt, symlinked-file, FIFO, and dangling-link targets are still atomically repaired; directory targets, including symlinks to directories, fail closed
    - a Darwin-only source-compiled test now covers the real Objective-C publisher and daemon lifecycle instead of relying only on shell helper stubs; the daemon-exec test waits for helper readiness before checking the settled process tree
*   **Result:** the unchanged live baseline produced 11 inode/mtime identities across 11 samples spanning 10.002 seconds despite one content hash. After rebuilding and reloading, 11 live samples retained one inode/mtime/hash identity; the helper remained the single child of the shell supervisor and no Barista runaways were detected. The focused native test also holds identity across explicit refreshes and daemon ticks while still replacing changed and corrupt snapshots.

### 0f. Single-Snapshot Native Front-App Discovery (Verified)
*   **Files:** `helpers/runtime_context_helper.m`, `tests/test_runtime_context_helper_publication.sh`
*   **Update:**
    - each native refresh now resolves the focused-window snapshot once and passes the same record through frontmost-app naming and matching-window selection
    - a matching focused window still takes the fast path; a minimized or mismatched snapshot still falls through to the ranked full-window list
    - the real Objective-C regression test logs exact fake-yabai commands and requires one focused-window query on both the common match and full-list fallback cases
*   **Result:** the normal no-override native refresh drops from three yabai launches (focused window, spaces, focused window again) to two, while its full-list fallback drops from four to three. This removes one subprocess per base tick without changing the cache schema, helper count, or polling cadence; explicit front-app override paths already skipped the naming query. After live reload, the runtime settled to one helper child, ten cache samples spanning 9.058 seconds retained one identity/hash, and a directional six-second helper sample accumulated 0.01 CPU-seconds, 52 context switches, and 338 BSD calls. When NSWorkspace or an override still supplies an app name, a transient failed focused query now proceeds directly to the full-window fallback instead of receiving an accidental second focused-query attempt.

### 0g. Event-Driven Native Front-App Refresh (Verified)
*   **Files:** `helpers/runtime_context_helper.m`, `main.lua`, `modules/items_left.lua`, `modules/runtime_daemon.lua`, `plugins/front_app.sh`, `scripts/runtime_context.sh`, `tests/test_front_app_plugin.sh`, `tests/test_items.lua`, `tests/test_runtime_context_helper.sh`, `tests/test_runtime_context_helper_publication.sh`, `tests/test_runtime_daemon.lua`
*   **Update:**
    - the existing helper observes application activation, active-space changes, and system wake through `NSWorkspace`; callbacks only schedule work, while the daemon main thread performs the yabai queries
    - related notifications debounce for 50 ms and cap scheduled deferral at 250 ms when the daemon thread is available; a separate five-second safety interval repairs missed or externally generated state changes without changing the shell media cadence
    - front-app clicks keep the direct popup toggle first, then consume one native refresh-and-return TSV asynchronously so same-app focus/property state is current without a second cache-read/validation query chain
    - Lua-only/helper-missing setups keep the portable one-second front-app producer; the native path keeps the same one-helper steady-state daemon topology, TSV schema, selection rules, and change-driven publication, while a popup click uses one short-lived refresh helper
    - the source-compiled test injects a private notification center, checks activation, active-space, and wake independently, and verifies that a sustained sub-debounce event stream cannot defer refresh indefinitely
*   **Result:** the read-only live baseline observed 20 helper forks across 10.501 seconds, exactly one focused-window/spaces pair per roughly one-second refresh. A matched first post-reload sample observed 6 forks across 10.504 seconds (70% fewer), and a settled final sample observed 4 across 10.501 seconds, matching the five-second safety cadence's stable reduction from about 120 to 24 yabai executions per minute (80%). Event and popup refreshes remain demand-driven. Twenty live query pairs measured a combined 16.447 ms median and 20.103 ms p95 before this cadence reduction.

### 0h. Batched Front-App Popup Apply (Verified)
*   **Files:** `modules/items_left.lua`, `plugins/front_app.sh`, `tests/test_front_app_plugin.sh`, `tests/test_items.lua`
*   **Update:**
    - the anchor, header, state, location, and four mutable action labels now travel in one animated SketchyBar argument vector instead of eight separate CLI processes
    - if the animated request fails, the exact same complete payload is retried once without animation; a second request failure keeps the existing best-effort behavior
    - the layout tells the plugin whether optional yabai action rows exist, so yabai-enabled layouts send eight `--set` groups while disabled-yabai or unavailable-yabai layouts send only the four available anchor/header/state/location groups and do not trigger a failed retry
    - deterministic tests require one successful client invocation, exact target/payload order, intact quoted/Unicode arguments, the configured SketchyBar binary, native-context and portable-context paths, and identical fallback payloads
*   **Result:** on the enabled-action topology, a same-session sequential 60-run renderer-only sample reduced median apply latency from 27.173 ms to 3.563 ms (86.9%) and p95 from 29.133 ms to 3.773 ms (87.0%). A same-session sequential 25-run live popup-refresh sample reduced end-to-end median from 79.948 ms to 54.832 ms (31.4%) and p95 from 86.069 ms to 58.181 ms (32.4%). Both observed profiles ran the old path first against the same settled Ghostty/Tiled context. Fresh native context discovery remains the dominant roughly 40 ms portion, so a new UI helper would add coupling for comparatively little remaining benefit.

### 0i. Adaptive Native Query Wait (Verified)
*   **Files:** `helpers/runtime_context_helper.m`, `tests/test_runtime_context_helper_publication.sh`
*   **Update:**
    - native yabai tasks now poll for completion every 1 ms during their first 20 ms, then return to the previous 10 ms cadence for slower work
    - the existing query deadline, `NSTask` termination, 50 ms grace period, forced-kill fallback, TSV schema, daemon topology, and portable path are unchanged
    - the source-compiled native test checks the wait-policy boundary directly and confirms that a query which ignores `SIGTERM` is gone when the bounded helper call returns
*   **Result:** a same-session randomized/interleaved 40-run live sample reduced native fresh-snapshot median from 30.439 ms to 17.001 ms (44.1%) and p95 from 31.521 ms to 18.714 ms (40.6%). Through the existing shell wrapper, median dropped from 40.791 ms to 28.009 ms (31.3%) and p95 from 42.986 ms to 30.950 ms (28.0%). The complete batched popup-refresh path dropped from 55.634 ms to 42.042 ms median (24.4%) and from 58.286 ms to 44.979 ms p95 (22.8%), without adding IPC, another daemon, or a native popup renderer.

### 0j. On-Demand Triforce Status (Verified)
*   **Files:** `modules/integrations/oracle.lua`, `plugins/oracle_triforce.sh`, `tests/test_oracle_triforce.sh`
*   **Update:**
    - removed the Triforce anchor's 45-second polling timer; click still toggles the popup first, then starts one background status refresh
    - live status now comes directly from Oracle's canonical `Scripts/Build/oos-triforce.sh status-json --barista` producer instead of depending on a machine-local workbench wrapper
    - the dynamic anchor, header accent, ROM, focus visibility/label, and Continue label update through one SketchyBar argument vector; invalid JSON applies nothing
    - refreshes coalesce behind one stale-aware lock, and the canonical producer runs in a dedicated process group with a four-second default deadline plus TERM/forced-kill cleanup; repeated clicks cannot accumulate status workers
    - explicit `triforce.label` text remains authoritative while automatic labels continue to follow the live status line
    - the focus row always exists as a hidden refresh target, and Continue resolves the current Oracle focus at click time rather than retaining a reload-time command
    - config-model construction performs no Oracle shell/Python/git snapshot; initial post-config, anchor-click, and wake events own refresh work, with the legacy anchor-only widget retained only when the canonical producer is unavailable; the retired `update_freq` state/command is removed
*   **Result:** the removed timer path measured 33.029 ms median and 35.071 ms p95 across 60 live runs. Removing it eliminates up to 80 useless runs per shown hour (1,920 per day) and keeps the roughly 100 ms canonical status snapshot on explicit event paths rather than making a repaired producer three times more expensive on the old timer.

### 1. Network & System Info (Mitigated)
*   **File:** `helpers/system_info_widget.c`
*   **Update:** Batched 5 separate `system()` calls into a single `sketchybar` invocation.
*   **Result:** Reduced 5 fork+exec cycles to 1 per update interval. Perl-based timeouts remain as safety.

### 2. Space Management (Verified Active Path)
*   **Files:** `plugins/refresh_spaces.sh`, `plugins/simple_spaces.sh`, `plugins/space.sh`, `plugins/space_visuals.sh`, `scripts/app_icon.sh`, `helpers/space_visual_helper.m`, `main.lua`
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
    - per-display creator items bind to the known spaces on their target display with associations enabled, so the add-space affordance stays visible without duplicating every creator across every monitor
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
    - `simple_spaces.sh` now prefers the cheaper Perl timing path before `python3`, so phase metrics no longer add as much timestamp-process overhead to the topology hot path
    - the space/creator click-action prefixes are now resolved once per run, and both full and incremental item loops reuse the preloaded icon cache directly instead of rechecking script paths or cache files per space
    - `simple_spaces.sh` now parses bar height and item membership in one jq pass over the shared bar snapshot instead of separate jq probes, and it now reads cached icon files with shell builtins instead of one `cat` subprocess per icon file
    - `simple_spaces.sh` now validates and parses the shared `yabai query --spaces` payload in one jq pass, so discovery no longer burns an extra jq subprocess just to confirm the payload is non-empty before parsing it again
    - the hidden `space_runtime` item now keeps `updates=false`, so SketchyBar does not autonomously force the visual batch script between the explicit topology/manual refresh paths
    - `space_visuals.sh` now ignores `SENDER=forced` runs, and `space.sh` no longer falls back to a full `space_visual_refresh` when there is no cached hover state to restore
    - active-space updates now trigger the dedicated `space_active_refresh` event instead of the legacy broad `space_change` event, so the active refresh path only wakes popup-manager/control-center consumers that still use active-space signals
    - the Triforce anchor no longer subscribes to space/display churn events that it does not actually handle
    - the delayed startup visual sync now runs as `startup_sync` and uses its own wider cooldown window, so it skips itself when a recent authoritative topology refresh already settled the spaces strip while still preserving the recovery path when topology did not run
    - `space_visuals.sh` now coalesces overlapping runs and cools down `front_app_switched` updates immediately after authoritative refreshes
    - `front_app_switched` now has a focused-space fast path: `space_visuals.sh` delegates current-space resolution to `scripts/front_app_context.sh`, updates only the focused visible space, and skips the full `yabai --windows` snapshot
    - `space_visuals.sh` now caches the `space.*` item lookup under `cache/space_visuals/space_items` and reuses it on the focused-space fast path, avoiding a full `sketchybar --query bar` on repeated `front_app_switched` visual refreshes
    - `refresh_spaces.sh` now passes the already-fetched spaces payload into `space_visuals.sh`, so authoritative visual refreshes reuse the same `yabai query --spaces` result instead of querying spaces twice
    - `space_active_refresh` now uses the same focused-space fast path as `front_app_switched`, so an active-space-only refresh no longer falls back to the full spaces + windows snapshot path when the focused-space helper already has the answer
    - pure active-space refreshes no longer emit a redundant `space_mode_refresh`; the existing `space_change` event is enough for the active-path listeners and cuts orchestration overhead on space switches
    - authoritative visual refreshes now resolve app state with scoped visible-space window queries instead of taking one global window snapshot for every space
    - when `bin/space_visual_helper` is available, `space_visuals.sh` batches those visible-space app lookups through one helper invocation and avoids per-space shell/jq parsing; the shell scoped-query path remains the fallback
    - `scripts/app_icon.sh --batch` resolves missing app glyphs for the helper-loaded visible apps in one script process before `space_visuals.sh` writes the app-glyph cache
    - `space_visuals.sh` now applies and persists a complete focused/visible/idle style set for each space, so hover restore uses `cache/space_visuals/style_state/` instead of re-deriving active state from a stale selected-space cache
    - the active spaces scripts (`refresh_spaces.sh`, `simple_spaces.sh`, `space_visuals.sh`) now all accept injected `BARISTA_*_BIN` overrides so shell smoke tests exercise the same runtime boundary deterministically
    - startup now schedules one delayed direct `space_visuals.sh` pass after the runtime subscriptions are back up, so the spaces strip settles to the real focused space after reload instead of relying only on the first topology-driven pass or the event/subscription race
    - contended `refresh_spaces.sh` runs now record the last pending reason and schedule one coalesced follow-up after the active lock clears, so display/space bursts do not spin duplicate topology work or silently drop the final topology state
*   **Result:**
    - per-space handlers are now hover-only
    - full rebuilds create fewer items and avoid unused popup rows
    - startup reloads produce both topology and visual refresh timings
    - the `space_visual_refresh` event can be triggered independently for focused visual updates.

### 2a. Music Menu Routine Path (Verified)
*   **Files:** `modules/integrations/music.lua`, `modules/items_left.lua`, `modules/ui_builder.lua`, `plugins/music_studio.sh`
*   **Update:** The music launcher stays click/hover driven only (`updates=false`), and its popup model points at the current `Studio/` songforge/studio CLI paths plus shallow kit folders. On the fully populated model, the initial surface is 13 rows instead of 24; secondary apps and kit/folder launchers remain available through the click-only `More Apps` and `Kits + Folders` children.
    The root toggle resets both children before opening or closing, nested actions close the child and root together, and the shell plugin only owns hover/status behavior.
*   **Result:** the Music menu keeps every launcher without periodic forced updates or presenting all 24 rows at once. The live first-open measurement is recorded in section 3e.

### 2b. Control-Center Popup Cleanup (Verified Active Path)
*   **Files:** `modules/integrations/control_center.lua`, `modules/items_left.lua`, `modules/ui_builder.lua`, `plugins/control_center.sh`
*   **Update:**
    - removed service-health, workspace dirtiness, and utility rows from the popup
    - stopped the live updater from computing dirty-repo and service-row state that no longer has a visible consumer
    - removed the synchronous config-time Yabai layout query; the widget seeds a `---` placeholder and the existing timeout-bounded post-config updater publishes the live layout
    - complete window-manager flags are reused while constructing popup rows instead of repeating capability and service probes
    - reduced the fully enabled root from 23 rows to 12; the click-only `cc.more` child keeps all 11 Layout Ops and App Defaults rows reachable
    - root toggles reset `cc.more`, child actions close both levels, and disabled/no-Yabai models omit the child and its registry entry
*   **Result:** the removed live layout query measured 11.20 ms median across 40 reads. In a same-session five-pair isolated sample, 20 popup-model builds dropped from 815.59 ms median to 7.93 ms (99.0%) after complete flags stopped repeating external probes; normal config still performs one shared health/capability snapshot before the bounded updater takes over.

### 3. Popup & Submenu Execution (Resolved)
*   **Files:** `helpers/popup_hover.c`, `helpers/popup_anchor.c`, `main.lua`, `modules/menu.lua`, `modules/ui_builder.lua`
*   **Update:**
    - `popup_hover` now passes a bounded argument vector directly to `execvp()` instead of rebuilding a command and routing it through `sh -c`
    - popup row names and properties remain single arguments, removing shell interpolation from the pointer hot path
    - the Apple anchor now selects the compiled `popup_anchor` helper through the normal runtime-backend resolver, with the shell implementation retained for Lua-only and helper-missing setups
    - the enhanced Apple-menu context forwards the resolved absolute SketchyBar binary to the native anchor, so launchd does not depend on Homebrew being present in `PATH`
*   **Result:** a 400-event no-op benchmark reduced popup-row hover median from 6.39 ms to 2.87 ms (55%); a 30-pair alternating live Apple-anchor sample reduced median handler time from 22.58 ms to 6.54 ms (71%) and p95 from 40.86 ms to 12.03 ms.

### 3a. Anchor Chip Styling (Verified)
*   **Files:** `modules/ui_builder.lua`, `modules/items_left.lua`, `modules/apple_menu_enhanced.lua`, `helpers/popup_anchor.c`, `plugins/lib/common.sh`, `plugins/popup_anchor.sh`
*   **Update:** Left-side popup anchors share one filled idle chip and `BARISTA_ANCHOR_*` hover-restore contract. The native anchor helper and shell fallbacks both restore configured idle background/border props instead of always clearing the background to transparent. One immediate post-config move batch now enforces Triforce → Music → Control Center → Front App before the delayed spaces topology pass.
*   **Result:** Apple, Triforce, Music, Control Center, and Front App keep a consistent visual language and deterministic order without adding query-before-toggle click controllers or racing independent move timers.

### 3b. SketchyBar Binary Resolution + Plugin Runaway Guard (Resolved)
*   **Files:** `plugins/lib/common.sh`, `plugins/space.sh`, `plugins/space_visuals.sh`, `plugins/refresh_spaces.sh`, `scripts/process_manager.sh`
*   **Update:**
    - plugin scripts now preserve the absolute `SKETCHYBAR_BIN` resolved by `common.sh` instead of re-running `command -v sketchybar` after the shared `sketchybar()` wrapper function exists
    - caller `PATH` remains ahead of fallback paths so tests and live wrappers can inject stubs safely
    - `process_manager.sh barista` and `process_manager.sh runaways` expose the live Barista process family and flag duplicated/hot plugin scripts without destructive cleanup by default
*   **Result:** space hover/visual scripts avoid self-recursive SketchyBar wrapper calls, and live CPU spikes can be diagnosed before cleanup.

### 3c. Space Visual Phase Attribution (Verified)
*   **Files:** `plugins/space_visuals.sh`, `bin/barista-stats.sh`, `plugins/lib/space_style.sh`, `helpers/space_visual_helper.m`, `scripts/app_icon.sh`
*   **Update:**
    - `space_visuals.sh` keeps the normal hot path coarse-timed, but `BARISTA_SPACE_VISUAL_PHASE_METRICS=1` adds phase fields for spaces payload, item lookup, state maps, visible app lookup, glyph resolution, style-state work, and SketchyBar apply
    - `barista-stats.sh show` summarizes those phase fields when detailed samples exist
    - visible-space app lookup can now be helper-backed and app glyph misses are batch-resolved before the main visual loop
    - style-state files are only rewritten when the saved state/properties differ, while hover restore still reads the same persisted state
    - focused/visible/idle style argument arrays are cached once per run, so full visual passes no longer re-render and re-split identical style properties for every space chip
*   **Result:** detailed attribution is available for targeted tuning without adding timing subprocesses to every routine visual refresh.

### 3d. Post-Config Startup Ordering (Verified)
*   **Files:** `main.lua`, `modules/items_left.lua`, `modules/menu_renderer.lua`, `modules/runtime_startup.lua`, `plugins/reload_sketchybar.sh`
*   **Update:**
    - layout effects, hover/submenu subscriptions, and Yabai signal registration enter one FIFO dispatch queue instead of running against an uncommitted item registry
    - the queue flushes after `sbar.end_config()` and converts generated leading `sleep N; ...` commands into native `sbar.delay` callbacks; if the installed Lua module rejects native delay scheduling, commands run immediately after commit rather than leaving detached sleeper processes
    - delayed callbacks use asynchronous `sbar.exec` without adding another detached shell layer
    - keyed pending commands collapse identical popup-dismissal and hover subscription intents, so an anchor shared by both contracts launches one SketchyBar subscription client instead of two
    - the supported reload helper no longer launches a redundant one-second detached spaces repair; it still waits for `space.1` and runs the same repair synchronously when startup did not create it
    - `items_left.lua` reports the optional popup parents actually created, so popup dismissal honors custom names and omits absent integrations
*   **Result:** item registration commits before external startup effects run, the normal delayed path no longer creates shell sleeper processes that can survive a process-replacing reload, and missing optional widgets cannot leave phantom popup-manager targets. A supported live restart on 2026-07-20 dispatched 111 initial plus two late post-config actions, sampled no `sleep 0.2`, `sleep 0.8`, or `sleep 1.0` processes, produced no new stdout/stderr item errors, and restored all queried core items plus both runtime sidecars; that run recorded 297 ms config wall time and 933 ms total reload time.

### 3e. Progressive Popup Disclosure (Implemented)
*   **Files:** `main.lua`, `modules/ui_builder.lua`, `modules/items_left.lua`, `modules/integrations/music.lua`, `modules/integrations/control_center.lua`, `plugins/front_app.sh`
*   **Update:** shared click-only child popups keep the frequently used root rows shallow. The fully populated Music root moves from 24 rows to 13 through `More Apps` and `Kits + Folders`; the Yabai-enabled Front App root moves from 29 rows to 18 through `More Window Actions`; and the fully enabled Control Center root moves from 23 rows to 12 through `More Layout Controls`, whose 11 rows contain Layout Ops and App Defaults.
    Root toggles close their children before changing root state, and nested actions close both levels in one SketchyBar request after the original action runs. `items_left.lua` reports its child popup names and `main.lua` merges them with menu submenu metadata before writing the runtime registry. Disabled and no-Yabai Control Center models omit the child.
*   **Result:** every launcher/window action remains reachable while the first popup surface is shorter. In 20 randomized live samples per Music and Front App root/path, the layout-only Music median fell from 92.43 ms to 66.54 ms (28.0%) with p95 108.56 ms to 79.48 ms; Front App fell from 107.54 ms to 77.30 ms (28.1%) with p95 115.09 ms to 94.72 ms. Configured-click medians also fell from 117.82 ms to 96.20 ms for Music and 127.59 ms to 115.10 ms for Front App. The Roland TR-1000 process remained near 100% CPU and after-state system load was higher; Front App's configured-click p95 was correspondingly noisy (136.64 ms to 156.32 ms), so the direct layout path is the primary acceptance signal.
    A separate same-method 20-sample Control Center run reduced the layout-only median from 86.90 ms to 57.48 ms (33.8%) and p95 from 94.00 ms to 62.97 ms. Its configured-click median fell from 114.21 ms to 84.44 ms (26.1%) and p95 from 126.41 ms to 92.11 ms. The SketchyBar PID stayed stable, every open-state check passed, no stderr lines were added, and all popup parents finished closed.

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
    - the left-side Oracle builder reuses one static model and defers its live status snapshot to the async controller; the control-center builder defers live layout discovery to its bounded post-config updater and reuses complete flags while composing popup rows
    - left-layout timing is now also broken out by subsection (`front_app`, `triforce`, `spaces`, `control_center`, `group`) so the remaining build-side cost can be targeted precisely
    - config-build and left-layout subsection timing now use an in-process profiling clock instead of spawning a timestamp subprocess for every probe; total `reload_time` remains wall-clock
    - `simple_spaces.sh` now derives active display and display count from the existing spaces payload in the normal path, avoiding a second `yabai --displays` query unless the focused display cannot be inferred
    - `space_topology_refresh` now records pure `simple_spaces.sh` topology time from the child metrics file instead of the entire `refresh_spaces.sh` runtime; the remaining orchestration is tracked separately as `space_refresh_overhead`
    - topology metrics temp files are now created lazily and live in `TMPDIR` instead of cluttering the Barista config/repo directory
    - `refresh_spaces.sh` now caches the last applied external-bar height and skips re-running `yabai -m config external_bar ...` on unchanged active-only refreshes
    - `refresh_spaces.sh` now resolves that external-bar height from the live SketchyBar bar before falling back to persisted `state.json`, so display-profile height normalization cannot leave yabai reserving a stale baseline
    - `refresh_spaces.sh` now derives display state, space topology state, active-space state, space count, and desired space indexes from one jq pass over the shared `yabai query --spaces` payload instead of multiple independent jq calls
    - active-only `space_items_present` checks now reuse one cached bar snapshot lookup instead of piping the bar item list through `grep` for each desired space index
    - `refresh_spaces.sh` now passes the shared spaces payload into `simple_spaces.sh`, and active-only refreshes reuse the persisted `cache/space_visuals/space_items` lookup instead of querying the full bar again when topology is unchanged
    - active-only refreshes now dispatch `space_active_refresh` once through SketchyBar instead of both triggering the event and separately re-running `space_visuals.sh`, removing duplicate focused-space visual work from the hot path
    - creator-only and incremental add/remove topology updates now sync existing creator items in place instead of tearing down and recreating the whole creator set when the creator item identity did not change
    - `refresh_spaces.sh` now parses child topology metrics with one shell read instead of a stack of `awk` probes, and it now prefers the cheaper Perl timing path before `python3` for its own wrapper timing
    - `runtime_daemon.stop_runtime_context_daemon()` now clears the whole runtime-context family on restart, including stale helper daemon and refresh children, so live focused-space probes no longer inherit orphaned runtime/query processes across reloads
    - `runtime_context.sh daemon` now launches `runtime_context_helper daemon` directly instead of backgrounding a shell function, removing the redundant nested shell layer from the live runtime path
    - topology and visual refresh durations are logged separately
    - config-build timing now flushes through one `events-batch` write instead of spawning `barista-stats.sh` once per config metric, removing a large artificial post-config cost from reload profiling
    - reload timing is now also split into wall-clock `reload_prep_time`, `reload_daemon_stop_time`, `config_build_wall_time`, and `reload_stats_flush_time`, so the blocking reload path can be attributed even when the Lua-side `config_build_time` stays tiny
    - topology refresh events now carry explicit strategy/counter metadata (`strategy`, `added`, `removed`, `updated`, `spaces`)
    - full-rebuild topology events now also carry `prepare_ms` and `apply_ms`, so `barista-stats.sh show` separates script-side preparation from the SketchyBar batch apply cost
    - the live stats now also split `full_rebuild` preparation into `discovery`, `build`, and `decision` phases so the remaining shell-side cost can be targeted more precisely
    - `barista-stats.sh` now writes JSONL and migrates legacy pipe-delimited logs aside
    - `barista-stats.sh show` summarizes the live runtime path and breaks topology timings out by strategy so incremental reorder/add-remove paths are measured separately from full rebuilds
*   **Result:** reload time, topology rebuild time, incremental topology update time, and visual refresh time are now measurable from the installed runtime.

## Remaining Considerations
1.  **Visible app lookup cost:** `space_visuals.sh` avoids full snapshots and batches helper-backed visible-space lookups when the compiled helper exists, but full visual passes still depend on yabai window data for each visible space.
2.  **Clock daemon coverage:** the current daemon path is verified live, but there is still no dedicated test coverage around `main.lua` startup instrumentation.
3.  **Topology rebuild cost:** `simple_spaces.sh` is materially cheaper after removing dead popup rows, but full rebuild remains the dominant startup cost.
4.  **Async I/O:** the current architecture is event-driven enough for daily use, but long-term migration to a fully async runtime remains the cleaner end state.
5.  **Fully event-driven media state:** the producer is now adaptive and change-detected, but Spotify/Music do not expose a shared portable event stream. A future native event source could remove the remaining bounded idle probe without weakening Lua-only/work-machine portability.

## Shell Script Optimization Summary
- **AWK Variable Naming**: Standardized to avoid collisions.
- **Binary Paths**: Fixed to `/opt/homebrew/bin/sketchybar` (or resolved via `paths.lua`).
- **Batching**: System-wide adoption of array-based argument building for `sketchybar` calls.
