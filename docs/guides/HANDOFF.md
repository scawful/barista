# Barista Handoff

Last updated: 2026-04-06
Scope: active runtime for `/Users/scawful/src/lab/barista`

## What Barista Owns

Barista is the ambient macOS bar layer.

- Barista owns glanceable status, popup sections, quick launch, and one-click entry into deeper tools.
- Barista does not own Oracle session state, Cortex host logic, or external app settings.
- If a workflow wants a deep control surface, Barista should launch it, not recreate it.

## Runtime Assumptions

Recommended live setup:

- `~/.config/sketchybar -> /Users/scawful/src/lab/barista`
- `skhd` and yabai window actions route through `scripts/yabai_control.sh`
- the active docs path for Apple-menu handoff notes is this file:
  - `docs/guides/HANDOFF.md`

Safe runtime commands:

```bash
./plugins/reload_sketchybar.sh
./bin/recover_sketchybar.sh
./bin/barista-stats.sh show
sketchybar --query bar
sketchybar --query <item>
```

Use raw `sketchybar --reload` only when intentionally measuring reload behavior.

## Active Runtime Path

Main ownership:

- `main.lua`
  - config build
  - delayed subscriptions
  - daemon lifecycle
  - reload instrumentation
- `modules/items_left.lua`
  - `front_app`
  - `triforce`
  - `control_center`
  - spaces startup wiring
- `modules/items_right.lua`
  - clock
  - system info
  - volume/media
  - battery
- `modules/menu.lua`
  - top-level menu ownership and fallback builder
- `modules/apple_menu_enhanced.lua`
  - active Apple menu builder

Runtime sidecars:

- `plugins/refresh_spaces.sh`
  - space topology coordinator
- `plugins/simple_spaces.sh`
  - space item creation and topology diff logic
- `plugins/space_visuals.sh`
  - space icon/highlight visual refresh
- `scripts/runtime_context.sh`
  - shared runtime cache supervisor
- `helpers/runtime_context_helper.m`
  - compiled front-app / focused-space helper
- `helpers/widget_manager.c`
  - steady-state daemon for right-side widgets when enabled
- `helpers/volume_popup_helper.m`
  - click-only CoreAudio/cache detail refresh for the volume popup; compiled
    setups use one acknowledged SketchyBar batch and retain `plugins/volume.sh`
    as the portable/failure fallback

## Current Interaction Contracts

### Apple Menu

- hover highlights only
- hover highlight auto-clears after the short bar timer
- click opens popup sections
- closes via popup-anchor global exit behavior
- must not set `POPUP_OPEN_ON_ENTER=1`
- owning files:
  - `modules/apple_menu_enhanced.lua`
  - `modules/menu.lua`
  - `helpers/popup_anchor.c`
  - `plugins/popup_anchor.sh`

### Triforce

- hover only highlights
- click toggles popup
- global exit dismisses popup
- owning files:
  - `modules/integrations/oracle.lua`
  - `plugins/oracle_triforce.sh`

### Front App Popup

- bar widget shows the current app icon, not the app name
- hover highlight auto-clears after the short bar timer
- click opens popup
- popup shows state, location, app actions, window actions, and move actions
- actions close the popup after firing
- owning files:
  - `modules/items_left.lua`
  - `plugins/front_app.sh`
  - `scripts/front_app_context.sh`
  - `scripts/yabai_control.sh`

## Current Yabai Window Rules

These are the live rules and should stay explicit.

### Same-display space moves

- plain `window-space` moves preserve the current window float state
- exception: if the destination space is `float`, the moved window is normalized to floating after the move

### Cross-display moves

- `window-display-next`
- `window-display-prev`

These adopt the visible destination space mode.

- moving into a `float` destination display floats the window
- moving into a managed destination display re-tiles the window

UI and shortcut routes must go through `scripts/yabai_control.sh`, not raw `yabai -m` display move commands.

### Front-app popup recovery actions

The popup now exposes:

- `Adopt Current Space Mode`
- `Send to Float Space`

Those are the preferred user-facing repair paths when a window lands in the wrong state.

## What Is Stable Now

- Apple menu is hover-highlight + click-open again
- Triforce is click-open, not hover-open
- right-side widgets use explicit click-open / dismiss flows
- runtime-context helper path is the active front-app / focused-space cache path
- spaces use split topology vs. visual refresh paths
- space icons and highlight restore are materially less flaky than the older per-item event path
- cross-display move policy is explicit and tested, even if current hardware only exposes one display

## Current Hot Spots

The main remaining runtime cost is still spaces, not config build.

Watch these buckets in `./bin/barista-stats.sh show`:

- `space_topology_refresh`
- `space_refresh_overhead`
- `space_visual_refresh`
- `reload_prep_time`
- `reload_daemon_stop_time`
- `config_build_wall_time`

Current guidance:

- do not guess on spaces perf
- measure before and after
- keep changes narrow
- do not reintroduce per-space event fanout when a batch event path already exists

## Verification Workflow

Use the smallest verification that actually covers the change.

### Lua changes

```bash
luac -p <changed lua files>
lua tests/run_tests.lua <relevant test files>
```

### Shell changes

```bash
bash -n <changed shell files>
bash tests/<relevant test>.sh
```

### Helper changes

```bash
clang -fsyntax-only helpers/<file>
cmake --build build --target <helper> sync_binaries
```

### Live checks

```bash
./plugins/reload_sketchybar.sh
./bin/barista-stats.sh show
sketchybar --query <item>
```

## Files To Reach For First

If the issue is about:

- Apple menu opening or layout:
  - `modules/apple_menu_enhanced.lua`
  - `modules/menu.lua`
- spaces timing or missing space icons:
  - `plugins/refresh_spaces.sh`
  - `plugins/simple_spaces.sh`
  - `plugins/space_visuals.sh`
  - `plugins/space.sh`
- front-app state or wrong window/location info:
  - `plugins/front_app.sh`
  - `scripts/front_app_context.sh`
  - `scripts/runtime_context.sh`
  - `helpers/runtime_context_helper.m`
- window move behavior:
  - `scripts/yabai_control.sh`
  - `tests/test_yabai_control_window_rules.sh`
- control-center popup behavior:
  - `modules/integrations/control_center.lua`
- volume/media popup behavior:
  - `helpers/volume_popup_helper.m`
  - `plugins/volume.sh`
  - `plugins/volume_click.sh`
  - `scripts/media_control.sh`

## Current Test Gaps

These are known weak spots, not reasons to stop moving.

- some broader shell harnesses around runtime-context and visual paths can still be flaky under constrained runners
- GUI/control-panel coverage is build/lint heavy, not behavior-test heavy
- live multi-display validation is blocked when yabai only reports one display

When that happens:

- prefer a narrower deterministic smoke test
- use a direct runtime probe over a broad flaky harness
- document the exact residual risk

## Open Priorities

### 1. Spaces perf

Still the highest-value engineering target.

Focus order:

1. `space_refresh_overhead`
2. `space_visual_refresh`
3. then any remaining topology `prepare/discovery`

### 2. Front-app popup clarity

The popup should make move-policy outcomes obvious before the click.

### 3. Runtime cleanup

Keep daemon ownership explicit.

- one shell supervisor where needed
- one helper daemon where needed
- no orphaned children across reloads

## Rules For The Next Agent

- read `README.md`, `docs/PERFORMANCE_AUDIT.md`, and `docs/troubleshooting/WIDGET_FIXES.md` first
- verify the live runtime path before assuming a source edit is active
- prefer the smallest live-path fix
- update docs when behavior changes
- do not silently mix hover-open and click-open on the same anchor
- do not broaden spaces event fanout without measuring the cost

## Short Command Sheet

```bash
# normal restart
./plugins/reload_sketchybar.sh

# recover missing bar
./bin/recover_sketchybar.sh

# show current runtime perf buckets
./bin/barista-stats.sh show

# rebuild helper after Objective-C/C changes
cmake --build build --target runtime_context_helper sync_binaries

# focused test examples
lua tests/run_tests.lua tests/test_items.lua tests/test_shortcuts.lua
bash tests/test_yabai_control_window_rules.sh
bash tests/test_refresh_spaces.sh
bash tests/test_space_visuals.sh
```

## Related Docs

- `README.md`
- `docs/PERFORMANCE_AUDIT.md`
- `docs/troubleshooting/WIDGET_FIXES.md`
- `docs/architecture/SKETCHYBAR_LAYOUT.md`
- `docs/STATE_SCHEMA.md`
