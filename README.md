# Barista ☕️

**The Cozy macOS Status Bar.**

Barista is a curated configuration for [SketchyBar](https://github.com/FelixKratz/SketchyBar) that balances aesthetics with power-user features. It is designed to be shared, easy to install, and configurable for different environments (Work vs. Home).

## Features

- **Dynamic Island**: Context-aware popups for volume, brightness, and music.
- **Profiles**: Switch between "Work", "Personal", and "Cozy" modes instantly.
- **Modular Architecture**: Lua-based configuration system decomposed for high performance and testability.
- **Integrations**: Optional support for Yabai (tiling), Skhd (hotkeys), Journal (org-mode capture/inbox), NERV (transfer queue + host monitoring), and Halext-org (task dashboard). Integrations are toggled per profile.

## Product Boundary

Barista is the ambient menu bar layer.

- Barista owns glanceable status, popup sections, quick launch, and one-click entry into deeper tools.
- Cortex owns the native host/runtime, notifications, secrets, and module shell.
- Oracle inside Cortex owns persistent AI sessions, agent modes, provider/model routing, and Zelda-first AI work.
- Janice Code owns cross-device persona/avatar and model-fleet workflows.

Barista may launch Oracle, Janice Code, or Cortex, but it should not duplicate Oracle's AI settings, Janice Code's model-fleet behavior, or Cortex host logic.

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
| **Girlfriend** | Warm colors, larger text, simplified metrics. No scary tiling. | **Disabled** | 🧸 Cozy |
| **Work** | High info density, meeting indicators, calendar integration. | Required | 💼 Pro |
| **Personal** | The default dev setup. Code, media, and tiling. | Required | ⚡️ Fast |

## Window Management (Yabai)

Barista includes optimized configurations for **Yabai** (window manager) and **Skhd** (hotkeys).
The installer can automatically set these up for you.

Window-manager status and controls are surfaced through the left-side
`control_center` widget and `front_app` popup actions.
The popup manager, helper popups, and the `toggle_control_center` shortcut all
target the same resolved control-center item name; the default remains
`control_center`.

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

**LaunchAgents:** The single place to edit the Barista orchestrator (SketchyBar + yabai + skhd at login) is `lab/barista/launch_agents/`. See [launch_agents/README.md](launch_agents/README.md). Recommended: use either this LaunchAgent or `brew services` for the three daemons, not both.

## Zelda Workbench

Barista now treats Zelda hacking as a two-layer surface:

- The left-bar `Triforce` widget is the shallow launcher.
- Oracle Hub is the deeper workflow surface.

Use Oracle Hub when you want session planning, Oracle status, build/test buttons, and tool launchers:

```bash
./bin/open_oracle_agent_manager.sh
```

Oracle Hub is intended to replace deep SketchyBar popup interaction for Oracle work. The SketchyBar side should stay shallow and quick.

In practice, the Triforce popup should stay close to three actions plus ROM context:

- `Continue: <current focus>`
- `Patch + Launch`
- `Open Oracle Hub`
- `ROM: oosNNNx.sfc`

## Customization

### Switching Profiles
```bash
# Switch to Cozy mode
./scripts/set_mode.sh girlfriend disabled

# Switch to Work mode
./scripts/set_mode.sh work required
```

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
./scripts/setup_machine.sh --yes --panel-mode tui --runtime-backend lua
./scripts/barista-debug.sh --lua-only --reload
```

See [docs/guides/WORK_MACHINE_GEMINI.md](docs/guides/WORK_MACHINE_GEMINI.md) for the Gemini-first upgrade flow.

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
  --work-domain yourcompany.com \
  --panel-mode tui \
  --runtime-backend lua
```

- **Hover animation:** In `state.json` or in `modules/state.lua` defaults, `hover_animation_duration` (default 8) and `hover_animation_curve` (default `sin`) control popup hover speed. Lower duration (e.g. 6) for even snappier feel.
- **Process Batching:** Barista minimizes process forks. Space topology rebuilds stay batched, and the post-rebuild visual pass now runs once through `plugins/space_visuals.sh` instead of per-space `space_change` handlers.
- **Widget Daemon:** `clock`, `system_info`, and `battery` can run as daemon-managed surfaces. Their steady-state updates come from the long-lived `widget_manager daemon`, while popup detail refresh still happens only on click.
- **Runtime Context Helper:** `scripts/runtime_context.sh` now prefers the compiled `bin/runtime_context_helper` for front-app and focused-space cache reads/writes, while the shell path still owns media/output state.
- **Spaces Diff Path:** `plugins/simple_spaces.sh` now updates `space.*` incrementally for reorder and add/remove topology changes instead of dropping the full spaces stack in those cases.
- **Non-blocking Spaces Startup:** `plugins/simple_spaces.sh` no longer stalls reload waiting for `front_app`; it falls back to the next available anchor and lets the async reorder path repair final placement once `front_app` appears.
- **Dedicated Spaces Startup Delay:** the initial spaces rebuild and `space_runtime` subscription now use a shorter post-config delay than the rest of the bar so `space.*` items land sooner after reload without retuning every other delayed subscription.
- **Precomputed Apple Menu Model:** the enhanced Apple-menu model is now prepared before `begin_config`, so menu path discovery and section building happen while the old bar is still visible instead of inside the blank reload window.
- **Direct Execution:** Hot-path C helpers use `execlp()` instead of `system()` to eliminate shell overhead and unnecessary forks.
- **Modular Load:** Configuration logic is split across focused modules (`shell_utils`, `paths`, `binary_resolver`) to ensure fast initialization.
- **Instrumentation:** `./bin/barista-stats.sh show` reports reload timing plus space topology and visual refresh timings from the live runtime, and now breaks space topology timings out by strategy (`full_rebuild`, `creator_only`, `incremental_reorder`, `incremental_add_remove`, etc.).
- **Config Build Metric:** `./bin/barista-stats.sh show` now reports `config_build_time` separately from total reload time, so the `begin_config` to `end_config` window can be tuned independently from spaces follow-up work.
- **Config Build Breakdown:** the same stats view now splits config build into menu render, left layout, right layout, and popup/submenu registry work, and now further separates left/right layout time into layout-table build vs. SketchyBar apply so reload tuning can target the actual slow phase.
- **Shared Left-Layout State:** the left-side Oracle and control-center builders now reuse one status/model snapshot per config pass instead of rediscovering the same runtime state twice during reload.
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
- **No More Forced Space Visual Passes:** the hidden `space_runtime` item now keeps `updates=false`, `space_visuals.sh` ignores autonomous `forced` runs, and `space.sh` no longer falls back to a full visual refresh when hover-state restore has no cached style to restore.
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
