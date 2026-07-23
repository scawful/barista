# Barista ☕️

**The Cozy macOS Status Bar.**

Barista is a curated configuration for [SketchyBar](https://github.com/FelixKratz/SketchyBar) that balances aesthetics with power-user features. It is designed to be shared, easy to install, and configurable across personal, work, restricted, and low-maintenance Macs.

## Features

- **Dynamic Island**: Context-aware popups for volume, brightness, and music.
- **Task Pulse**: Optional, local-first task status and capture actions without committing personal task paths.
- **Profile variants**: Switch between Minimal, Cozy, Personal, Work, and Restricted Work modes.
- **Modular Architecture**: Lua-based configuration system decomposed for high performance and testability.
- **Integrations**: Optional support for Yabai (tiling), Skhd (hotkeys), Journal (org-mode capture/inbox), NERV (transfer queue + host monitoring), and Halext. Integrations are toggled per profile or machine.

## Product Boundary

Barista is the ambient menu bar layer.

- Barista owns glanceable status, popup sections, quick launch, and one-click entry into deeper tools.
- Cortex owns the native host/runtime, notifications, secrets, and module shell.
- Oracle inside Cortex owns persistent AI sessions, agent modes, provider/model routing, and Zelda-first AI work.
- Scawfulbot owns cross-device persona/avatar and model-fleet workflows.

Barista may launch local workflow tools through opt-in interface extensions, but it should not duplicate those projects' deeper settings or host logic.

## Quick Install

To install Barista and its dependencies:

```bash
# Clone the repo
git clone https://github.com/scawful/barista.git ~/.local/share/barista

# Run the installer
~/.local/share/barista/scripts/install.sh
```

The installer will guide you through:
1. Installing dependencies (SketchyBar, Lua, Fonts).
2. Choosing a **Profile** (see below).
3. Configuring **Yabai/Skhd** (optional).

## Profiles

| Profile | Description | Yabai | Vibe |
| :--- | :--- | :--- | :--- |
| **Minimal** | Clean, distraction-free. Good for new users. | Optional | ⚪️ Clean |
| **Cozy** | Warm colors, larger text, simplified metrics. | **Disabled** | 🧸 Cozy |
| **Work** | Emacs and work-oriented spaces; personal integrations stay opt-in. | Required | 💼 Pro |
| **Personal** | The default dev setup. Code, media, and tiling. | Required | ⚡️ Fast |

Triforce/Oracle and Music Studio are Personal-profile integrations. Minimal,
Cozy, Work, and restricted-work leave both off unless that Mac explicitly opts
in through its ignored local state or `barista_config.lua`.

Task configuration is portable by default: committed defaults contain no task
paths and keep the Task Pulse widget off. Applying `work` or `restricted-work`
also clears task sources and disables Task Pulse so a synced work Mac cannot
inherit a personal board. Halext remains an explicit local opt-in on Work
rather than an implied profile dependency.

When an older non-Personal state first upgrades to schema v2, Barista removes
only the exact former pair of bundled personal task paths. Personal profiles,
custom source lists, and explicit task opt-ins are preserved. Re-enable any
work-specific source locally after switching to Work.

## Window Management (Yabai)

Barista includes optimized configurations for **Yabai** (window manager) and **Skhd** (hotkeys).
The installer can automatically set these up for you.

Window-manager status and controls are surfaced through the left-side
`control_center` widget and `front_app` popup actions.
The popup manager, helper popups, and the `toggle_control_center` shortcut all
target the same resolved control-center item name; the default remains
`control_center`.

Window move commands now normalize the destination state when a managed window
is sent into a `float` space: the window is moved first, then floated if the
target space is actually `float`. Cross-display window moves now adopt the
visible destination space mode in both directions, so a floating window dropped
onto a managed (`bsp` / `stack`) display is re-tiled and a tiled window dropped
onto a float display is floated.
The Yabai-enabled `front_app` popup now trims its previous 18-row root to 13
rows. `Quit App`, `Float Window`, `Adopt Current Space Mode`, and `Fullscreen`
stay direct; the existing click-only `front_app.more` child is labeled `More
Actions` and grows from 12 rows to 17 by adding `Hide App`, `Force Quit`,
`Sticky`, `Topmost`, and `Center` beside the presets and display/space moves.
Opening or closing the root still resets the child, and a child action still
closes both popup levels after it runs. Disabled and no-Yabai paths keep the app
actions on the root and omit the child. App-default rows can persist
"this app floats" / "this app tiles" rules through `scripts/yabai_control.sh
app-default-current <float|tile|unset>`. The Yabai-enabled Control Center keeps
its mode, space-layout, and shortcut rows on a 12-row root; its click-only
`More Layout Controls` child holds the 11 Layout Ops and App Defaults rows.
Opening or closing the root resets that child, and a child action closes both
levels. Disabled and no-Yabai paths omit the child entirely.

Reload shortcuts should use `plugins/reload_sketchybar.sh`; avoid raw
`sketchybar --reload` for normal use so overlapping reload requests stay
serialized and health-checked against `front_app`.

- **Enable**: Run installer and select "Window Manager Mode: Required".
- **Disable**: Run `./scripts/set_mode.sh <profile> disabled`.

## Source universe: runtime and overlay

**Recommended:** Make the SketchyBar runtime a symlink to the Barista repo so edits are live:

```bash
# If ~/.config/sketchybar already exists, back it up first
mv ~/.config/sketchybar ~/.config/sketchybar.bak
ln -s ~/src/lab/barista ~/.config/sketchybar
```

**Personal overlay:** For per-machine additions (e.g. Oracle of Secrets integration, workflow shortcuts), use the overlay in `~/src/config/dotfiles/sketchybar-overlay/`. Apply it with:
`~/src/config/dotfiles/scripts/apply_sketchybar_overlay.sh`
Optionally pass the target dir (default: `~/.config/sketchybar`). If the runtime is a symlink to lab/barista, the overlay is written into the repo. See `config/dotfiles/sketchybar-overlay/README.md`.

**Skhd and yabai_control:** Space/layout keybindings in skhd call `yabai_control.sh`. To support both "Barista deploy" and "dotfiles-only" setups, use the wrapper: `~/.local/bin/yabai_control_wrapper.sh` (from `config/dotfiles/bin/yabai_control_wrapper.sh`). Ensure that wrapper is on your PATH and installed (e.g. dotfiles link `bin/` to `~/.local/bin`).
For shortcut health, run `~/.config/sketchybar/scripts/yabai_control.sh doctor`
to list loaded skhd files, verify the generated Barista shortcut include, and
flag duplicate bindings. For a full shortcut map, run
`~/.config/sketchybar/scripts/yabai_control.sh shortcuts`; it lists every loaded
skhd binding by source file and flags raw yabai commands or missing script
targets. For window-rule drift, run
`~/.config/sketchybar/scripts/yabai_control.sh rules-audit`; unmanaged utility
apps should default to `manage=off sub-layer=normal`, with topmost kept as an
explicit manual action.

**LaunchAgents:** The single place to edit the Barista orchestrator (SketchyBar + yabai + skhd at login) is `lab/barista/launch_agents/`. See [launch_agents/README.md](launch_agents/README.md). Recommended: use either this LaunchAgent or `brew services` for the three daemons, not both.

## Zelda Workbench

Barista now treats Zelda hacking as a two-layer surface:

- The left-bar `Triforce` widget is the shallow launcher.
- Oracle Hub is the deeper workflow surface.

Use Oracle Hub when you want session planning, Oracle status, build/test buttons, and tool launchers:

```bash
./bin/open_oracle_agent_manager.sh
```

Oracle Hub is intended to replace deep SketchyBar popup interaction for Oracle work. The SketchyBar side should stay shallow and quick, but it now keeps one launcher section for the core Zelda tools that belong beside the session controls.
Those Zelda launchers live in the Triforce popup rather than being duplicated in the Apple menu.

In practice, the Triforce popup should stay close to:

- a `ROM: oosNNNx.sfc` context row
- a session section with `Continue: <current focus>` and `Patch + Launch`
- an app launcher section with `Oracle Hub`, `Yaze`, `z3ed`, and `Mesen2 OoS`

The Triforce anchor toggles immediately, then refreshes its ROM, focus, Continue,
and alert fields asynchronously from Oracle's canonical
`Scripts/Build/oos-triforce.sh status-json --barista` output. The refresh also
runs after wake and once after configuration; there is no periodic
Triforce timer. All mutable fields are applied in one SketchyBar request.

For quick workflow access, the generated skhd shortcuts include:

- `⌘⌥T` to open a terminal window (Ghostty when installed, Terminal as fallback)
- `⌘⌥Z` to launch `z3ed` in Ghostty
- `⌘⌥D` to open the clock popup's local `Focus` / `Next` / `Waiting` /
  `Blocked` task focus; configure its sources per machine

## Task Pulse

Task Pulse is an optional right-side chip for a configured local task board. It
is absent unless both `widgets.task_focus=true` and at least one
`menus.calendar.task_sources` entry are present. Clicking the chip opens a
bounded popup with `Summary`, `Focus`, `Next`, `Waiting`, and `Blocked` rows plus
`Capture Task`, `Open Board`, and a single menu-only focus-session action. When
the provider is `syshelp`, the popup also includes `Complete Focus…`: it takes a
fresh focus snapshot, asks for confirmation, then revalidates the same unique
focus identity before marking its exact title and section done and refreshing
task state. File-only providers stay read-only and never render the completion
action. The focus-session row starts or stops a
25-minute session without adding another bar widget, daemon, or polling timer.
The closed chip stays narrow:
its task icon is followed only by the open count (or `Clear` / `Tasks !` for the
empty and source-or-provider-unavailable states). Task titles remain inside
bounded popup rows.

Keep the paths in ignored `state.json` or `barista_config.lua`, not in a shared
profile:

```json
{
  "widgets": {
    "task_focus": true
  },
  "menus": {
    "calendar": {
      "task_provider": "files",
      "task_sources": ["~/src/folio/tasks/active.md"]
    }
  }
}
```

`task_provider` supports `files` and `syshelp`. The portable `files` provider
reads Markdown/Org sources but does not invent mutation rules: capture opens the
configured board. The opt-in `syshelp` provider reads
`syshelp plan tasks json` and captures with `syshelp plan tasks add`. If launchd
cannot resolve that command, set machine-local `menus.calendar.syshelp_path` to
its absolute executable path. When a task source exists, generated skhd
shortcuts also include `⌘⌥N` for conditional task capture. Successful syshelp
capture and external task tools can trigger
`task_state_changed`, which refreshes Task Pulse without adding a polling timer.

The existing clock popup can also show one next meeting from an explicitly
configured local `menus.calendar.meeting_cache_file`. This is a read-only menu
row: Barista never launches calendar authentication or syncing, and hides the
row when the cache is unavailable.

## Customization

### Switching Profiles
```bash
# Switch to Cozy mode
./scripts/set_mode.sh cozy disabled

# Switch to Work mode
./scripts/set_mode.sh work required
```

`set_mode.sh` preserves explicit machine-local overrides so profile switching
is reversible. To scrub personal task paths and integrations when preparing a
work Mac, use `setup_machine.sh --profile-variant work` (or
`--restricted-work`) instead.

### Configuration
Edit `~/.config/sketchybar/state.json` to toggle widgets and appearance, or use `barista_config.lua` for overrides that survive the GUI. See [docs/guides/CUSTOMIZATION.md](docs/guides/CUSTOMIZATION.md) for state.json, profiles, themes, and fonts; [docs/STATE_SCHEMA.md](docs/STATE_SCHEMA.md) for the live runtime key schema; [docs/architecture/SKETCHYBAR_LAYOUT.md](docs/architecture/SKETCHYBAR_LAYOUT.md) for which file defines each bar item. To validate theme files: `lua scripts/validate_theme.lua [theme_name]`.

For the stricter ownership split between Barista and Oracle tooling, keep Barista focused on bar configuration and use Oracle Hub for Oracle work.

```json
{
  "profile": "minimal",
  "widgets": {
    "battery": true,
    "wifi": false
  }
}
```

### Work Google Apps Menu
Populate customizable Work Google app entries in the Apple menu:

```bash
# Use defaults
./scripts/configure_work_google_apps.sh --replace

# Use workspace domain routes
./scripts/configure_work_google_apps.sh --domain yourcompany.com --replace

# Use custom app list
./scripts/configure_work_google_apps.sh --from-file ./data/work_google_apps.example.json --replace
```

### Fonts + Alternate Panel
Install missing fonts, repair `state.json` to match available families, and set a preferred alternate control panel mode:

```bash
./scripts/install_missing_fonts_and_panel.sh --yes --panel-mode tui
```

For managed/work Macs that should avoid compiled helpers entirely:

```bash
./scripts/setup_machine.sh --yes --restricted-work --domain yourcompany.com
./scripts/barista-debug.sh --lua-only --reload
```

`--restricted-work` is the no-compiled/no-yabai lane. It uses the Python
standard-library configurator at `scripts/machine_profile.py` to pin
`runtime_backend=lua`, disable yabai/skhd shortcut state, prefer the TUI/manual
settings path, write `data/machine.local.json`, and add basic Work Apps menu
rows without requiring `jq` or a native app build.

For direct CLI menu edits on a restricted machine:

```bash
# Add or refresh the default Google Workspace menu rows
./scripts/configure_work_google_apps.sh --domain yourcompany.com --replace

# Add a single custom Apple-menu row
python3 ./scripts/restricted_config.py menu-item \
  --label "Runbook" \
  --url "https://example.com/runbook" \
  --section work
```

See [docs/guides/WORK_MACHINE_GEMINI.md](docs/guides/WORK_MACHINE_GEMINI.md) for the Gemini-first upgrade flow.

### Interface Extensions

Use script-backed extension rows for local launchers and machine-specific
actions instead of committing personal app paths into the default Apple menu.
Extensions can appear in the Apple menu, disabled-yabai `front_app` / Control
Center replacement rows, and the LM Studio popup.

```bash
# Personal Mac only; this file is ignored by git.
cp data/interface_extensions.personal.example.json data/interface_extensions.local.json
python3 ./scripts/machine_profile.py apply --variant personal --report
```

Work and restricted profiles leave personal extensions and the LM Studio widget
off by default. See [docs/guides/INTERFACE_EXTENSIONS.md](docs/guides/INTERFACE_EXTENSIONS.md).

### Machine Profile Variants

For another Mac, keep machine-local choices in a gitignored profile file instead
of hardcoding host-specific behavior into the Lua runtime:

```bash
# Probe available tools and helpers
./scripts/detect_capabilities.sh

# Apply a normal machine variant
python3 ./scripts/machine_profile.py apply \
  --variant personal \
  --state ~/.config/sketchybar/state.json \
  --report

# Apply the script-only restricted variant
python3 ./scripts/machine_profile.py apply \
  --variant restricted-work \
  --domain yourcompany.com \
  --report

# Inspect the resolved machine profile and feature gates
python3 ./scripts/machine_profile.py report
```

The machine profile is written to `data/machine.local.json` next to
`state.json` by default and is ignored by git. The committed
`data/machine_profiles.example.json` documents the built-in variants.

If you want the compiled widget daemon to be explicit in persisted state instead of
automatic detection, set:

```json
{
  "modes": {
    "widget_daemon": "auto"
  }
}
```

Supported values are `auto`, `enabled`, and `disabled`.

For Oracle workflow, `open_control_panel.sh --oracle` forwards directly to Oracle Hub without changing the broader panel-mode preference.

### Update Another Mac
Push the latest repo changes to a remote Mac and apply work profile extras:

```bash
./scripts/update_work_mac.sh \
  --host user@work-mac.local \
  --target origin/main \
  --restricted-work \
  --work-domain yourcompany.com \
  --skip-restart
```

- **Hover animation:** In `state.json` or in `modules/state.lua` defaults, `hover_animation_duration` (default 8) and `hover_animation_curve` (default `sin`) control popup hover speed. Lower duration (e.g. 6) for even snappier feel.
- **Process Batching:** Barista minimizes process forks. Space topology rebuilds stay batched, and the post-rebuild visual pass now runs once through `plugins/space_visuals.sh` instead of per-space `space_change` handlers.
- **Widget Daemon:** `clock`, `system_info`, and `battery` can run as daemon-managed surfaces. The compiled daemon updates the clock on minute boundaries, system info every 10 seconds, and battery every 120 seconds; popup detail refresh still happens only on click.
- **Native System Info Detail Refresh:** on default compiled setups, `widget_manager daemon` owns the 10-second compact CPU/memory anchor; daemon-disabled and portable setups retain `plugins/system_info.sh` plus the routine `system_info_widget` helper. Clicks toggle immediately and start `system_info_popup_helper popup_refresh` in the background. `modules/items_right.lua` sends the exact enabled subset of `cpu,mem,disk,net,swap,uptime,procs`; the helper gathers only those rows and applies them as one bounded SketchyBar Mach update. Actionable Top CPU replaces the redundant standalone Activity Monitor row while enabled; disabling Top CPU restores that direct action. Setting `system_info_items.actions=false` preserves every enabled metric, keeps Top CPU informational, and omits the Activity Monitor and System Settings launchers. The popup stays flat because a controlled five-versus-seven-row progressive-disclosure A/B found no measurable root-open improvement. Mach VM statistics use the same active+wired+compressed memory model as the anchor, SystemConfiguration discovers Wi-Fi interfaces without a hardware-list child, and the remaining bounded probes cover disk, route/optional SSID, and a compact system-wide top-process lookup. Missing helpers and native invocation, payload, or IPC failures use the strict `plugins/system_info.sh popup_refresh` fallback, while individual probe failures render safe placeholders. Lua-only mode explicitly ignores stale native binaries; see the performance audit for current phase attribution and artifacts.
- **Event-driven task surfaces:** the closed calendar popup has no periodic header timer. Opening it via the clock or `⌘⌥D` refreshes on demand and applies all calendar rows in one SketchyBar call, while optional Task Pulse refreshes on click, `task_state_changed`, and `system_woke`.
- **Adaptive Runtime Context:** `scripts/runtime_context.sh` prefers the compiled `bin/runtime_context_helper` for front-app/focused-space work. The native helper reuses one focused-window snapshot per refresh, wakes on app/space/wake events, and retains a five-second safety refresh while preserving unchanged cache bytes. Front-app popup clicks toggle first, then consume one fresh returned snapshot asynchronously and apply all available anchor/detail updates in one SketchyBar request. The portable media path uses one bounded player snapshot, probes less often when idle, and likewise avoids unchanged media/output publication. Explicit Lua-only profiles keep compiled helpers disabled even if an old binary is present, including popup refreshes; their portable front-app producer retains the base cadence.
- **Batched Space Visual Helper:** full visual passes prefer `bin/space_visual_helper` for one helper-backed visible-space app lookup, then resolve missing app glyphs through one `app_icon.sh --batch` call before the single SketchyBar apply.
- **Spaces Diff Path:** `plugins/simple_spaces.sh` now updates `space.*` incrementally for reorder and add/remove topology changes instead of dropping the full spaces stack in those cases.
- **Non-blocking Spaces Startup:** `plugins/simple_spaces.sh` no longer stalls reload waiting for `front_app`; it falls back to the next available anchor and lets the async reorder path repair final placement once `front_app` appears.
- **Dedicated Spaces Startup Delay:** the initial spaces rebuild and `space_runtime` subscription now use a shorter post-config delay than the rest of the bar so `space.*` items land sooner after reload without retuning every other delayed subscription.
- **Stable Left-Side Order:** one post-config batch places Triforce → Music → Control Center → Front App before the delayed spaces rebuild, avoiding independent move timers that could strand Music after the space buttons.
- **Per-Display Space Creator:** each `space_creator.<display>` is associated with the known spaces on only its target display, so multi-monitor setups show one `+` per monitor instead of every creator on every bar.
- **Precomputed Apple Menu Model:** the enhanced Apple-menu model is now prepared before `begin_config`, so menu path discovery and section building happen while the old bar is still visible instead of inside the blank reload window.
- **Shared Popup UI Builder:** repeated popup toggles and menu-style rows now go through `modules/ui_builder.lua`, keeping click-open anchors direct while detail refreshes happen asynchronously. Front App and Control Center popup rows use the same row/header/separator helpers as Triforce and Music.
- **Progressive Popup Disclosure:** on the fully populated Personal/Yabai models, Music's initial surface drops from 24 rows to 13 by moving secondary launchers into `More Apps` and `Kits + Folders` children, Front App's enabled root drops again from 18 rows to 13 while its renamed `More Actions` child grows from 12 rows to 17, and Control Center drops from 23 rows to 12 by moving its 11 Layout Ops/App Defaults rows into `More Layout Controls`. Front App keeps Quit, Float, Adopt Space Mode, and Fullscreen direct while Hide, Force Quit, Sticky, Topmost, and Center join the existing presets and moves in the child. These children open only on click, Music keeps only one sibling child open, root toggles reset them first, and their actions close both popup levels. Disabled/no-Yabai Front App keeps app actions direct and omits its child; Control Center likewise omits its child when controls are disabled or unavailable. A same-daemon A/B cut the direct Front App layout median another 23.9%; see the performance audit for full results and configured-click variance.
- **Direct Popup Execution:** Popup-row hover passes bounded arguments directly from `popup_hover` to SketchyBar, and native-helper setups use compiled `popup_anchor` for the Apple anchor; portable fallbacks remain available.
- **Native Volume State + Detail Refresh:** Compiled setups use `volume_popup_helper` for initial state, `volume_change`, and click-time detail refreshes (CoreAudio + bounded runtime-cache reads + one SketchyBar request/reply). Stable hardware-controlled outputs stay native, show `HW` / `Volume: Hardware controlled`, and hide unavailable mute until a software-controllable output restores it. Lua-only/helper-missing, explicitly disabled, transient CoreAudio/device-read, and IPC-failure paths retain `plugins/volume.sh`; missing `SwitchAudioSource` keeps unusable route rows hidden without adding another widget.
- **Modular Load:** Configuration logic is split across focused modules (`shell_utils`, `paths`, `binary_resolver`) to ensure fast initialization.
- **Instrumentation:** `./bin/barista-stats.sh show` reports reload timing plus space topology and visual refresh timings from the live runtime, and now breaks space topology timings out by strategy (`full_rebuild`, `creator_only`, `incremental_reorder`, `incremental_add_remove`, etc.).
- **Process Diagnostics:** `./scripts/process_manager.sh load` prints a compact current load snapshot, `barista` reports the SketchyBar/yabai/skhd/runtime-context process family, and `runaways` flags hot or duplicated Barista plugin scripts without killing them.
- **Opt-in Visual Phase Metrics:** set `BARISTA_SPACE_VISUAL_PHASE_METRICS=1` for detailed `space_visuals.sh` phase attribution in `barista-stats.sh show` without adding timing subprocesses to the normal visual hot path; visible app/glyph lookups are batched when helpers are available, style arguments are cached per run, and unchanged style-state files are not rewritten.
- **Config Build Metric:** `./bin/barista-stats.sh show` now reports `config_build_time` separately from total reload time, so the `begin_config` to `end_config` window can be tuned independently from spaces follow-up work.
- **Config Build Breakdown:** the same stats view now splits config build into menu render, left layout, right layout, and popup/submenu registry work, and now further separates left/right layout time into layout-table build vs. SketchyBar apply so reload tuning can target the actual slow phase.
- **Non-blocking Integration Models:** the left-side Oracle builder creates one shared static menu model without running the Oracle status command inside config construction. Control Center likewise defers its live Yabai layout query to the bounded post-config updater and reuses complete window-manager flags instead of probing them again while building popup rows.
- **Post-config Commit Queue:** layout effects, hover/submenu subscriptions, and Yabai signal registration are collected during construction and flushed only after `sbar.end_config()`. Configuration-time delays use native `sbar.delay` callbacks instead of detached sleeper shells, duplicate hover/dismissal subscription intents collapse to one client call per item, the supported reload path relies on its existing synchronous missing-space fallback instead of scheduling a redundant repair sleeper, and popup dismissal registers optional left-side anchors and nested popup parents only when they were actually created.
- **Left-Layout Section Metrics:** the same stats view now also breaks left-layout build into `front_app`, `triforce`, `spaces`, `control_center`, and group assembly so the next reload fix can target the slow subsection instead of the whole left side.
- **Cheap Timing Probes:** config-build and left-layout section metrics now use an in-process profiling clock so measuring reload hot paths no longer adds extra timestamp subprocesses; end-to-end `reload_time` still uses wall-clock.
- **Spaces Discovery Reuse:** `simple_spaces.sh` now derives active display and display count from the already-fetched `yabai query --spaces` payload in the normal path, keeping the separate displays query only as a fallback.
- **Topology vs. Overhead Metrics:** `space_topology_refresh` now reflects pure `simple_spaces.sh` topology time, while `space_refresh_overhead` reports the remaining orchestration work around triggers, visual refresh invocation, and external-bar follow-up.
- **Full-Rebuild Phase Timing:** space topology stats now expose `full_rebuild` preparation vs. SketchyBar batch-apply time so reload tuning can target the slower half instead of guessing.
- **Prep-Path Reuse:** `plugins/simple_spaces.sh` now reuses one state-file read, one bar snapshot, and one sorted pass over yabai space data across the full-rebuild preparation path.
- **Cached Prep Reads:** full-rebuild prep now also reuses one display-state snapshot and one signature-cache read instead of re-querying yabai/displays or rescanning `.spaces_signatures` multiple times.
- **Cheaper Full Rebuild Prep:** when a reload starts from an empty `space.*` snapshot, `plugins/simple_spaces.sh` now skips diff-signature work entirely and bulk-loads cached space icons once instead of reading one cache file per space.
- **Cheaper Spaces Build Loop:** `plugins/simple_spaces.sh` now resolves space/creator action prefixes once per run, reuses the preloaded icon cache for both full and incremental item assembly, and uses the cheaper shell clock path for its phase timing.
- **Cheaper Spaces Wrapper Path:** `plugins/refresh_spaces.sh` now derives display/space/active signatures and space count in one jq pass, caches the live `space.*` item lookup for active-only checks, parses topology metrics in one shell read, and uses the cheaper shell clock path for its own timing.
- **Cheaper Spaces Discovery Path:** `plugins/simple_spaces.sh` now parses the bar snapshot in one jq pass and reads cached icon files with shell builtins instead of spawning a `cat` per icon file.
- **Single-Pass Spaces Query Parse:** `plugins/simple_spaces.sh` now validates and parses the `yabai query --spaces` payload in one jq pass, so the retry loop no longer pays for a separate JSON validation subprocess before building the discovery arrays.
- **No More Forced Space Visual Passes:** the hidden `space_runtime` item now keeps `updates=false`, `space_visuals.sh` ignores autonomous `forced` runs, and `space.sh` restores from persisted per-space style state instead of falling back to a full visual refresh.
- **Clear Active Spaces:** focused spaces use a filled lavender pill with a white border, visible inactive spaces use a stronger dark pill with a subtle border, and hover restores the saved focused/visible/idle state.
- **Dedicated Active-Space Event:** active-space updates now use `space_active_refresh` instead of the legacy broad `space_change` fan-out, so the active-space path only wakes the popup manager and control-center consumers that still need it.
- **Startup Visual Sync Cooldown:** the delayed `startup_sync` visual pass now uses its own cooldown window and skips itself when a recent authoritative topology refresh already settled the spaces strip, so reload no longer pays for a redundant second full visual pass.
- **Batched Config Metrics:** config-build timing now flushes to `barista-stats.sh` in one batch instead of one shell invocation per metric, so reload profiling no longer creates a large artificial post-config cost.
- **Wall-Clock Reload Breakdown:** `barista-stats.sh show` now separates reload prep, daemon stop, config-build wall time, and stats flush time, so reload latency can be attributed to the actual blocking phase instead of one undifferentiated `reload_time`.
- **Tuning:** See [docs/PERFORMANCE_AUDIT.md](docs/PERFORMANCE_AUDIT.md) for the active runtime model and performance checklist.

## Testing

Barista includes a comprehensive test suite of **94+ tests** across its Lua modules.

```bash
./scripts/barista-verify.sh          # Full smoke test (binaries, shell, lua)
lua tests/run_tests.lua              # Run Lua unit tests only
./scripts/rebuild.sh --verify       # Rebuild all and run tests
```

## Troubleshooting

- **Bar not showing?** Prefer `./bin/recover_sketchybar.sh`.
- **Need a normal interactive restart?** Use `./plugins/reload_sketchybar.sh` or the Apple-menu reload action instead of raw `sketchybar --reload`.
- **Bar comes up empty after reload or launch-agent restart?** Run `./bin/recover_sketchybar.sh`.
- **Recovery still leaves the bar empty or startup hangs at `require("sketchybar")`?** Reinstall SbarLua, then relaunch:
  `(rm -rf /tmp/SbarLua && git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua && make install)`.
- **Icons missing?** Run `./scripts/barista-fonts.sh --apply-state --report` and re-run `./scripts/barista-doctor.sh --fix`.
- **Need to debug without C/C++ helpers?** Run `./scripts/barista-debug.sh --lua-only --reload`.
- **Yabai acting weird?** Check `System Settings > Privacy & Security > Accessibility`.

---
*Maintained by Scawful. Part of the Halext ecosystem.*
