# SketchyBar Layout Map

Quick reference: which file defines each bar item, which plugin script runs for updates, and which events they subscribe to. Use this to jump to the right place when editing the bar.

**Defining file:** [main.lua](../../main.lua) orchestrates; left-side items are registered in [modules/items_left.lua](../../modules/items_left.lua), right-side items in [modules/items_right.lua](../../modules/items_right.lua). Popup item helpers live in [modules/popup_items.lua](../../modules/popup_items.lua).

---

## Left side (order: left → right)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `popup_manager` | `plugins/popup_manager.sh` | `space_change`, `display_change`, `display_changed`, `display_added`, `display_removed`, `system_woke` | Invisible; handles popup dismissal. It intentionally ignores `front_app_switched` during normal runtime so clicks that cause focus churn do not immediately close the popup that just opened, and skips dismissal during the 1.5 s handoff after a popup opens on another display. |
| `display_density` | `plugins/display_density.sh` | `display_change`, `display_changed`, `display_added`, `display_removed`, `system_woke` | Invisible, and only present when `appearance.auto_display_density` is on; recomputes the display density fingerprint and reloads only when rotation/resolution changes the mode. |
| `popup_switch` (click helper) | `helpers/popup_manager.c`; shell fallback `plugins/popup_manager.sh` | direct root/child click scripts | Reads the atomically published, generation-bound topology and issues one target-last SketchyBar mutation. Root switches close other roots plus every child; child switches close unrelated branches while preserving the requested child's ancestor chain. The separately named native alias is protocol-checked once at config time, so an older or incompatible binary cannot receive the new CLI after a source-only upgrade. |
| `space_runtime` | `plugins/space_visuals.sh` | `space_visual_refresh`, `front_app_switched`, `system_woke` | Invisible; single batch visual updater for all spaces. `front_app_switched` runs are coalesced after topology refresh, the focused-space fast path goes through `scripts/front_app_context.sh`, and full visual passes prefer `bin/space_visual_helper` plus `app_icon.sh --batch` for visible app/glyph lookup before one SketchyBar apply. |
| `triforce` | `plugins/oracle_triforce.sh` | `mouse.entered`, `mouse.exited`, `system_woke`; async click refresh | Hover only highlights the anchor. Click toggles immediately, then the controller takes one canonical Oracle status snapshot and batches the mutable anchor/popup fields. No periodic timer is installed; the legacy anchor-only widget is only a missing-producer fallback. |
| `music_studio` | `plugins/music_studio.sh` | `mouse.entered`, `mouse.exited` | Music launcher beside Triforce. Active name comes from `menus.music.item_name`; popup rows are app/workflow/kits launchers from `modules/integrations/music.lua`. Routine updates are disabled; its root toggle resets the click-only child popups while the plugin only owns hover/status work. |
| `control_center` | `plugins/control_center.sh` | `mouse.entered`, `mouse.exited`, `space_active_refresh`, `space_mode_refresh`, `system_woke` | Space-scoped layout controls with live selection and target identity; `cc.more` holds Arrange Windows, `cc.settings` holds global Bar Settings. Popup open asynchronously refreshes the target. |
| `shortcut_mode` | — | direct `skhd` mode hooks | Hidden by default. The personal leader map shows `LEADER` or `AGENT` here and hides it on return to default mode, leaving the Control Center's layout label untouched. |
| `front_app` | `plugins/front_app.sh` | `front_app_switched` | Click opens popup (app/window controls). Compiled popup refreshes call `bin/runtime_context_helper fresh-front-app` directly with an absolute yabai path, while helper-missing, failed, and Lua-only paths retain the portable wrapper/context fallback. |
| `triforce.*` (popup) | `plugins/oracle_triforce.sh` + shared hover script | on-open/wake status apply; launcher clicks | Play rows contain staged-build status, `Play`, `Load now`, the newest `Dev <topic>` build, and optional `Ganondorf test` from local `paths.ganondorf_launcher` / `BARISTA_GANONDORF_LAUNCHER`. The fight row executes its private packet and checkpoint. Apps are `Yaze`, `z3ed`, and `Mesen2 OoS`; `z3ed` launches a Ghostty-backed terminal session when installed. |
| `music.studio.*` (popup) | (hover script) | — | The fully populated root stays shallow: `yams`, Logic Pro, and **sp-xcx** (`YamsSP1.app` / `SP-XCX.app`) stay direct when installed; stock SP-1 Utility remains under More Apps. Workflow shortcuts stay direct, and `music.studio.more_apps` / `music.studio.kits` open the secondary apps and Kits/Folders on click. Nested launcher actions close the child and `music_studio` together. |
| `cc.*` (popup) | `plugins/control_center.sh` | — | The root shows live space identity and Manual/Tile/Stack selection. `cc.more` owns arrangement operations; `cc.settings` owns global integration visibility and shortcuts. `cc.feedback` appears on failure. Space actions use `scripts/space_menu_action.sh` and remain visible after success or failure. Disabled/no-Yabai models retain settings for re-enabling controls. |
| `front_app.*` (popup) | `plugins/front_app.sh` | — | Root shows app, live window state/location, and immediate window controls. `front_app.move` groups moves, `front_app.defaults` owns saved app rules, and `front_app.more` groups advanced window/app actions. `scripts/window_menu_action.sh` binds mutations to the shown identity and retains visible errors. Disabled/no-Yabai paths retain app actions and Desk extensions. |
| `space.1` … `space.N` | `plugins/space.sh` | `mouse.entered`, `mouse.exited` | Dynamic; created by `plugins/refresh_spaces.sh` → `plugins/simple_spaces.sh`. With yabai unavailable, Barista falls back to `spaces.count` / macOS Spaces preferences / a 5-space default so non-yabai profiles still show a space strip. |
| `space_creator*` | `plugins/space_creator.sh` | `mouse.entered`, `mouse.exited` | Dynamic add-space affordance. Per-display creators use their target display plus that display's current space-index list with `ignore_association=off`, producing one visible `+` on each monitor rather than duplicating every creator across every bar. |

Legacy note: the standalone `yabai_status` widget path was removed. Window-manager controls now belong to `control_center` and `front_app` popup rows.

---

## Right side (order: right → left)

| Item(s) | Plugin script | Events subscribed to | Notes |
|--------|----------------|----------------------|--------|
| `agents` | `plugins/agents.sh` → `scripts/agent_sessions.py` | `system_woke` | Optional agent manager (`widgets.agents`; personal profile only). The closed label is blank unless sessions wait on you (a question, a permission dialog, or a plan to approve); then it shows how many, in red. Refreshes every 30 s and on click with one Python pass and one batched SketchyBar call. |
| `agents.*` (popup) | `scripts/agent_sessions.py` | — | One row per tool (`Codex 1 · 1 need you · 88% wk`: session count, how many wait on you, and the Codex rate-limit window), up to eight session rows that jump to the owning app/window (those waiting on you first, in red, with their question), and a `Local` submenu. Data comes from local files only: Codex rollouts, `~/.claude/sessions`, Cursor agent transcripts, and `gemini` processes. Archived chats are dropped and rows use each app's chat name, read from Codex `state_*.sqlite` `threads`, Claude Desktop `claude-code-sessions`, and Cursor `state.vscdb` `composerData` (read-only). Claude usage is not available locally. |
| `lmstudio` / `lmstudio.*` | `plugins/lmstudio_model.sh` | — | The `Local` submenu inside the agents popup: LM Studio state, open, `interface_extensions` presets on the `lmstudio` surface, and unload. |
| `clock` | `plugins/clock.sh` (or C `clock_widget`) | — | When `modes.widget_daemon` resolves on, routine updates come from `widget_manager daemon`; popup = calendar. |
| `clock.calendar.*` | `plugins/calendar.sh` | — | Exactly 14 configured rows: month header, weekday header, six-week grid, date/time summary, one optional cached meeting, and compact `Focus` / `Next` / `Waiting` / `Blocked` local task summaries. Derived weekend, month-progress, and week/day footer rows are not materialized. Clock clicks toggle immediately and refresh asynchronously; `⌘⌥D` forwards through that same live click owner, preserving exclusive switching and second-press dismissal. The popup has no closed-state polling timer, never initiates calendar auth/sync, and one batched SketchyBar call applies the exact topology. |
| `ai_resource` | `plugins/ai_resource_toggle.sh` | `ai_resource_update` | AI resource indicator |
| `system_info` | `plugins/system_info.sh` + `system_info_widget` | — | The shell wrapper retains hover/events and portable behavior. Routine updates prefer the compact native helper or `widget_manager daemon`; they do not refresh popup rows. |
| `system_info.*` (popup) | `system_info_popup_helper` with `plugins/system_info.sh popup_refresh` fallback | — | Click toggles immediately, then refreshes the exact enabled dynamic-row subset asynchronously. Top CPU opens Activity Monitor itself, so the standalone Activity Monitor row appears only when Top CPU is disabled; System Settings remains direct. `system_info_items.actions=false` keeps metrics visible, makes Top CPU informational, and removes both static launchers. A measured nested-details prototype did not improve root-open latency, so this bounded popup intentionally remains flat. Static actions are not metric targets. |
| `volume` | `plugins/volume.sh` | `volume_change` | The shell wrapper retains hover and portable behavior, while compiled initial/`volume_change` updates delegate to `bin/volume_popup_helper`. Click toggles immediately and refreshes asynchronously. Stable hardware-controlled outputs remain native; Lua-only/helper-missing, disabled, transient CoreAudio/device, and IPC failures use `plugins/volume.sh`. `plugins/volume_click.sh` remains a compatibility wrapper. |
| `volume.*` (popup) | `bin/volume_popup_helper` (state + click detail) | — | Exactly 12 configured functional rows: prefixed `Volume`, `Output`, and `Now Playing` state; four output routes; three transport controls; mute; and settings. Duplicate heading/separator chrome is not materialized. The native path reads CoreAudio plus bounded shared `runtime_context` caches and applies ten updates (the anchor plus nine mutable popup targets) in one request/reply. Hardware-controlled outputs show `HW` and hide unavailable mute; software-controllable outputs explicitly restore it. `scripts/media_control.sh` owns playback/output actions, and action rows close the popup after firing. |
| `battery` | `plugins/battery.sh` | `system_woke`, `power_source_change` | Shell wrapper for hover/events; routine anchor updates still prefer `widget_manager` or the widget daemon. Click toggles immediately, then launches the portable detail refresh asynchronously. |
| `battery.*` (popup) | `plugins/battery.sh popup_refresh` | — | One `pmset` snapshot and one `ioreg` snapshot are parsed in-process, then the anchor plus five mutable detail rows are applied as one ordered six-target/20-property SketchyBar batch. AC/charging handling and action-row dismissal are unchanged; no popup row, helper, timer, or daemon was added. |

---

## Brackets (visual grouping)

- Optional `triforce` → optional `music_studio` → optional/custom-named `control_center` → hidden-by-default `shortcut_mode` → `front_app`; only successfully created optional items enter the left group, and one post-config batch enforces that order before spaces are rebuilt
- optional `agents` + optional `afs_approvals` + `clock` + `system_info` (right group)
- `volume` + `battery` (right group)

## System Info Path

1. [modules/items_right.lua](../../modules/items_right.lua) creates only the
   enabled dynamic rows in canonical order:
   `cpu,mem,disk,net,swap,uptime,procs`. It exports that exact comma-separated
   allowlist to both native and shell refreshers; an empty dynamic model is
   represented as `none`. The actionable Top CPU row also replaces the duplicate
   Activity Monitor action while present; disabling Top CPU restores that static
   action without changing the helper allowlist. The independent `actions` flag
   removes the Activity Monitor and System Settings launchers while preserving
   dynamic rows; Top CPU remains a refresh target but loses its click action.
2. On default compiled setups, `widget_manager daemon` owns the periodic compact
   anchor update. Daemon-disabled and portable setups retain
   `plugins/system_info.sh`, which delegates to the routine `system_info_widget`
   when allowed. Popup rows are never part of any routine payload.
3. A click toggles `popup.system_info` first, then launches
   `system_info_popup_helper popup_refresh` asynchronously. The alias is built
   from `helpers/system_info_widget.c`, but its separate filename prevents an
   older routine-only `system_info_widget` from being selected as the new popup
   entrypoint during an upgrade.
4. The native helper collects only the enabled rows and submits one batched,
   bounded SketchyBar Mach payload. CPU, active+wired+compressed memory, swap,
   uptime, SystemConfiguration Wi-Fi discovery, and interface-address work use
   direct APIs. Bounded absolute-path probes cover `/System/Volumes/Data` disk
   usage (falling back to `/` only when that mount is absent), the default route,
   an optional SSID lookup, and the system-wide top process through `/bin/df`,
   `/sbin/route`, `/usr/sbin/networksetup -getairportnetwork`, and compact
   `/bin/ps` output. The selected process PID is hydrated in-process when
   permissions allow, with the dependable accounting name as fallback.
5. Missing popup helpers and native invocation/IPC failures run the strictly
   parsed `plugins/system_info.sh popup_refresh` fallback. That action cannot
   recurse into `system_info_widget`. Lua-only layouts and layouts without a
   resolved routine helper also set `BARISTA_SYSTEM_INFO_NATIVE_DISABLE=1`, so
   a stale executable left in `bin/` is ignored for routine work. Both parsers
   reject unknown, duplicate, or malformed row lists before targeting any
   popup row.

## Control Center Path

Default runtime path:

1. [main.lua](../../main.lua) resolves the active control-center item name once.
2. [modules/items_left.lua](../../modules/items_left.lua) creates the left-bar item and passes the resolved name into popup creation.
3. [modules/integrations/control_center.lua](../../modules/integrations/control_center.lua) renders space rows against `popup.<item_name>`, arrangement rows against `popup.cc.more`, and integration/shortcut settings against `popup.cc.settings`. Saved app rules belong to `popup.front_app.defaults`.
4. `items_left.lua` and `items_right.lua` report all successfully created optional popup and submenu parents; `main.lua` merges those names with menu metadata plus the enabled agents root before atomically registering the exact runtime lists for dismissal and switching.
5. [modules/shortcuts.lua](../../modules/shortcuts.lua) generates
   `toggle_control_center` against that same resolved target. Persisted skhd
   commands use `scripts/invoke_popup_click.sh` to dispatch the live item's
   generation-bound click instead of caching its per-reload token.
6. [modules/popup_action.lua](../../modules/popup_action.lua) attaches helper popups to the resolved control-center popup parent instead of assuming `popup.control_center`.

The default item name is `control_center`. If `integrations.control_center.item_name`
is set in `state.json`, the runtime uses that value consistently across those paths.

---

## Popup click path

Normal click-open anchors route through `main.lua`'s `popup_toggle_action()` /
`modules/ui_builder.lua` into `bin/popup_switch`, with
`plugins/popup_manager.sh` as the portable fallback. A root switch sends one
SketchyBar argument vector: every other registered root is set off, every child
is reset, and the requested root toggles last. A child switch closes the other
registered children and toggles its target last without touching the owning
root. For deeper menus, ancestor relationships keep every containing child open
while sibling and unrelated branches close. This preserves second-click closure
while making a move from Front App or Music into Control Center dismiss the
previous two-level surface.

The enhanced Apple model applies the same rule without adding another bar
widget. When at least two of LM Studio, ChatGPT, Claude, and Cursor are rendered,
their existing launcher rows move beneath the click-only
`menu.tools.ai_apps` child; a lone launcher remains direct. A child action runs
through the existing asynchronous menu-action helper, then one batched close
turns off the child, every containing Apple fly-out, and `apple_menu`. On the
fully populated Personal model this keeps AFS Browser, Cortex, and Ghostty on a
12-row root instead of the former 15-row root.

On macOS, the compiled helper serializes that exact vector as one bounded,
double-NUL-terminated request to the canonical SketchyBar Mach service. It keeps
the CLI path for custom binaries, unsupported platforms, oversized payloads,
explicit `BARISTA_POPUP_MACH_DISABLE=1`, and transport failures that occur before
the kernel accepts the message. Because the final operation is a toggle, an
accepted send is at-most-once: a missing, malformed, or semantic-error reply is
never retried or replayed through the CLI. Missing or malformed replies are
treated as delivered; an explicit semantic error returns failure. This IPC shape
is a private SketchyBar implementation detail; the exact argv and portable
manager remain the stable compatibility boundary.

Do not put yabai display-focus queries, detail refresh helpers, or plugin update
controllers in this generic click path; those can make real mouse clicks look
dropped even when script-only tests pass. `front_app`, `control_center`,
Triforce, Music, and right-side refresh popups mutate visibility first, then
retain their status/detail work asynchronously. Popup action rows still close
their owning levels after running.

Menu metadata, left- and right-layout metadata, the enabled agents root, and the
fixed right-side roots form the authoritative registry. One versioned manifest
atomically publishes its deduplicated roots, children, and ancestor chains
within the loader's shared limits, so custom names and only actually created
children enter the switch vector. Each rendered click embeds the current
manifest generation token. Missing, malformed, or stale-generation topology
therefore fails open to the requested target only, including when a failed
publication cannot remove the prior file. The
distinct native alias and one-time protocol check prevent stale helpers from
intercepting the new CLI; missing aliases retain the shell or direct/local-reset
fallback.
The global popup manager should not subscribe to `front_app_switched`; app focus
can churn while SketchyBar handles a click, which makes menus appear to ignore
the click by opening and immediately closing.
Popup anchors also do not subscribe to `mouse.exited.global` in normal runtime,
and the global popup manager listens to real `space_change` rather than the
visual-only `space_active_refresh`; both events can arrive during the same focus
transition as a click. Use a second click, popup action rows, or real
space/display/wake events to dismiss.
Left-side popup anchors share a filled idle chip and `BARISTA_ANCHOR_*`
hover-restore contract through `modules/ui_builder.lua`, implemented by
`helpers/popup_anchor.c` or the `plugins/lib/common.sh` fallback. Hover should
restore that configured idle chip instead of clearing the anchor to transparent.
The Apple anchor uses compiled `bin/popup_anchor` when native helpers are
available and falls back to `plugins/popup_anchor.sh` in Lua-only or portable
setups. Both receive the resolved SketchyBar binary through
`BARISTA_SKETCHYBAR_BIN`, including the enhanced Apple-menu context. Actionable
popup rows use `bin/popup_hover`; that helper executes the
SketchyBar update directly without a nested `sh -c`.

## Events and triggers

- **space_change**, **space_mode_refresh**: Added as sketchybar events in main.lua. Real `space_changed` yabai signals now route through `refresh_spaces.sh`, which emits `space_change` only when the active space truly changed and emits `space_mode_refresh` after active/topology updates.
- **space_visual_refresh**: Added as a dedicated post-topology and on-demand visual refresh event; handled by `space_runtime`.
- **task_state_changed**: Added as the local task refresh event; successful syshelp capture and explicit external refresh actions can trigger it. No bar widget subscribes to it since the Task Pulse chip was removed; task summaries live in the calendar popup.
- **Yabai signals** (space_changed, space_created, space_destroyed, display_*) are wired in main.lua `watch_spaces()` and all point at `refresh_spaces.sh` so cache/lock handling stays in one place.
  Signal registration is emitted as a `post_config_call`, so it runs only after the SketchyBar configuration commits.
  If a signal arrives while `refresh_spaces.sh` already owns the topology lock,
  the script writes the pending reason and schedules one delayed follow-up after
  the lock clears, coalescing event bursts into a single final refresh.

---

## Runtime Sidecars

- **`widget_manager daemon`** owns steady-state updates when the compiled runtime is enabled: clock on minute boundaries, system info every 10 seconds, and battery every 120 seconds. Its supervisor loop sleeps for one second between due checks.
- **`scripts/runtime_context.sh daemon`** owns shared runtime caches under `cache/runtime_context/`. The portable front-app producer stays on the base tick; media uses one bounded versioned snapshot at playing/running/idle cadences of 1/2/3 ticks, output topology stays on the base tick, and unchanged media/output snapshots are not republished. When the compiled helper is active, the supervisor passes it a separate five-second front-app safety interval without changing the shell cadence.
- **`bin/runtime_context_helper`** owns the hot front-app / focused-space cache path when the compiled helper is present. It refreshes on application activation, active-space changes, and wake, coalesces related notifications before doing serialized query work, and keeps a five-second safety refresh for missed/external state changes. Each refresh shares one focused-window snapshot across app naming and selection, then compares bounded regular-file bytes before atomic publication so unchanged front-app state keeps a stable cache identity.
- **`plugins/front_app.sh`** owns the mutable front-app anchor and popup labels. Compiled popup refreshes invoke `runtime_context_helper fresh-front-app` directly with the resolved absolute yabai path; helper failure falls through to one portable wrapper pass without retrying the same native helper, and Lua-only mode never selects it. The plugin derives all labels from that one context snapshot and applies every available target in one animated SketchyBar request, with one identical non-animated retry when that request fails. `items_left.lua` suppresses the Yabai-only update groups on disabled-yabai or unavailable-yabai layouts so expected missing rows do not force the retry.
- **Lua-only ownership:** `main.lua` launches the runtime-context daemon with `BARISTA_LUA_ONLY=1` when `runtime_backend=lua`, so an executable helper left on disk is ignored. System Info independently carries `BARISTA_SYSTEM_INFO_NATIVE_DISABLE=1` into its shell wrapper, preventing a stale `system_info_widget` from bypassing that boundary.
- **`scripts/front_app_context.sh`** reads that cache first, then falls back to direct yabai/System Events discovery.
- **`scripts/media_control.sh`** reads cached player/output state first, but still dispatches playback and output-switch actions directly.
- **`scripts/process_manager.sh barista|runaways`** inspects the live process family and flags duplicated/hot Barista plugin scripts without cleanup by default.

---

## Where to edit

- **Bar appearance** (height, padding, colors, fonts): main.lua → appearance/state values and `sbar.bar()` / `sbar.default()`.
- **Add/remove a left-side item:** main.lua (search for `sbar.add("item",` and `position = "left"`) or items_left module after refactor.
- **Add/remove a right-side item:** main.lua (search for `position = "right"`) or items_right module after refactor.
- **Change what a widget does:** Edit the corresponding script in `plugins/`; System Info native routine/popup behavior is shared by `helpers/system_info_widget.c` with `plugins/system_info.sh` as the event/portable fallback, while volume click-detail behavior is split between `helpers/volume_popup_helper.m` and `plugins/volume.sh`.
- **Change popup contents:** `modules/items_left.lua` for front-app and Desk extension rows, `modules/integrations/control_center.lua` for Control Center rows, and `modules/items_right.lua` for agents/Local/calendar/system-info/volume rows.
- **Change task snapshot semantics:** `scripts/task_snapshot.py`; keep source/provider paths machine-local.
- **Change control-center popup rows:** `modules/integrations/control_center.lua`.
- **Change control-center item placement/wiring:** `modules/items_left.lua` and `main.lua`.
