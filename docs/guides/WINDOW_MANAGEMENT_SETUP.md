# Window Management Setup

Barista separates live window actions, saved app defaults, and saved space
layouts. SketchyBar displays their state; Yabai applies window/layout changes;
skhd routes keyboard commands to the same Barista actions.

## Daily controls

1. **App icon** changes the window shown in the menu. Moves are
   grouped under **Move This Window**; window presets and app actions are under
   **More Actions**. The menu captures the window ID and app name and
   rejects an action if that target no longer exists. **Always on top** and
   **All spaces** show On/Off directly in this menu. Clicking either toggles
   that property; neither changes the saved app default. If an app owns the
   pin, Barista reports that it could not remove it instead of claiming success.
2. **App icon → App Defaults** sets how future windows from that app are managed.
   These choices are separate from a one-time change to the current window.
   Removing a Barista default leaves other Yabai rules in force.
3. **Control Center → Layout** selects Manual, Tile, or Stack for the displayed
   space. The live selection is marked. An accepted change is verified before
   saving, and follows the space UUID across desktop reordering.
4. **Control Center → Arrange Windows** contains balance, rotate, and mirror.
   **Bar Settings** contains bar integration visibility and shortcut service
   control. Failed shortcut/window/space commands keep an error visible.

A visual refresh never changes the layout. Changing focus must not unexpectedly
restore an older layout preference. Startup restores saved app rules after the base rules, pins each saved space
layout, and only then sets the default for other/new spaces. This avoids
momentarily tiling a saved Manual space during startup. Yabai skips spaces with
explicit layout overrides when applying a global default ([Yabai 7.1.18
implementation](https://github.com/koekeishiya/yabai/blob/v7.1.18/src/space_manager.c#L241-L254)).

## State and service ownership

| Responsibility | Owner | Inspection |
| --- | --- | --- |
| Current spaces, windows, rules | Yabai | `yabai -m query --spaces`, `yabai -m rule --list` |
| Saved layout/app choices | `state.json`, `scripts/yabai_state.py` | `python3 scripts/yabai_restore.py --dry-run` |
| Startup replay | `scripts/yabai_restore.py --startup`, invoked after app rules in yabairc | Dry-run above; `--rules-only` excludes layouts |
| Shortcut service preference | `scripts/toggle_shortcuts.sh` | `scripts/toggle_shortcuts.sh status` (read-only) |
| Bar startup/helpers | `launch_agents/barista-launch.sh`, `modules/runtime_daemon.lua` | `scripts/barista-doctor.sh --report` |

`space_modes_by_uuid` stores canonical layout choices. `space_modes` and
`space_mode_uuids` retain compatibility with index-based editors. A missing
UUID is skipped instead of applying its setting to a different desktop at the
old number. Explicit legacy edits release conflicting old UUID bindings.
See [State Schema](../STATE_SCHEMA.md) for the complete format.

The supervisor starts eligible installed services in Yabai → skhd → SketchyBar
order. Starting a running service does not replace its process. Its environment
is local to its LaunchAgent; it does not publish global `launchctl setenv`
variables. The installer publishes a validated plist atomically and passes
script paths as separate arguments, including paths with spaces.

The bar's integration mode changes neither current windows nor running
services. On supervisor startup, `auto` starts installed Yabai, `required`
requires its services, `optional` leaves Yabai startup to its own service, and
`disabled` skips Yabai/skhd. Independently enabled LaunchAgents retain their
own login behavior. Shortcut Off additionally disables and stops the selected
skhd LaunchAgent; On enables and starts that same owner. It does not install a
second Homebrew service as a fallback.

## Installed sources

| Component | Active source |
| --- | --- |
| SketchyBar | `~/.config/sketchybar` → your Barista checkout |
| Yabai | `~/.config/yabai/yabairc`, often a dotfiles symlink; mirror `extras/yabai/yabairc` changes there |
| skhd | `~/.config/skhd/skhdrc`, including the generated Barista bindings |
| Services | `com.asmvik.yabai`, `com.koekeishiya.skhd`, `homebrew.mxcl.sketchybar`; coordinated by `dev.barista.control` |

The generated shortcut include is published atomically and only when its bytes
change. Malformed supplementary workflow data is rejected before either output
is published. Regenerate with `lua helpers/generate_shortcuts.lua`; skhd watches
loaded configuration files. Use `skhd --reload` if automatic loading is disabled.
`scripts/yabai_control.sh shortcuts` inventories loaded includes and conflicts.

K0 WINDOW bindings use `yabai_control.sh`, so keyboard and menu actions share
state handling. The six interactive BROWSE searches launch in a real terminal;
mode is captured before launching. Unassigned K0 slots remain unassigned, and
legacy `cd`-only navigation slots still do not navigate an already open app.
Cortex shortcuts resolve the existing native launcher through
`open_local_workflow.sh cortex`.

## Runtime verification and recovery

Hidden `space_runtime` and `display_density` items have updates enabled with
zero polling frequency. The native `display_change` event reaches display-density
refresh and popup dismissal. Daemon cleanup matches complete invocations for
the selected runtime; it rechecks identity before TERM and KILL.

1. Run `scripts/yabai_control.sh doctor` for a read-only service/config check.
   `doctor --probe-focus` explicitly tests focus capability; `doctor --fix`
   may change service state.
2. Run `scripts/yabai_control.sh rules-audit` and
   `python3 scripts/yabai_restore.py --dry-run` before replaying saved choices.
   Mesen/Yaze use an intentional below layer; that policy is not an error.
3. Reload the bar using `plugins/reload_sketchybar.sh`, then inspect
   `sketchybar --query bar`, `sketchybar --query space_runtime`, and
   `scripts/barista-doctor.sh --report`.

The older native control panel still uses a whole-document state writer and
optimistic Apply feedback. Use the menu for verified layout/app actions. The
menu and TUI Python writers share one canonical-path lock; legacy Lua/native
writers do not yet participate in that locking protocol.

A source test does not establish physical DisplayLink reconnect/sleep behavior
or hardware key delivery.

## Claude floating above other windows

Claude standard windows start with `sub-layer=below sticky=off`, without a
`manage` override. Floating and tiling choices therefore remain independent of
stacking. Turning Always on top off returns the window to its app's level:
`normal` for a Raised app, otherwise `below`, the sub-layer used by tiled
windows; `auto` would put a floating window back above them.
The named `claude-window-layer` rule is present in both the shipped yabairc
and the active dotfiles configuration. Explicit saved app defaults can override
base rules.

An app-owned native level above normal is a separate condition. This rule
cannot prevent Claude from changing its own native level during computer use;
the audit reports `app-topmost` if that happens.

## Spaces stop updating, or Mission Control drags snap back, after yabai restarts

Barista's yabai signals (space and display changes, and the Mission Control
guard that keeps a space's windows with it when you drag the space to another
display) are registered by SketchyBar when it loads, and a yabai restart
forgets them. When SketchyBar registers them it also writes
`~/.local/state/barista/yabai_signals.sh`; the yabairc replays that file at the
end of startup when SketchyBar is running. Check with
`yabai -m signal --list`: expect the `sketchybar_*` labels next to `load-sa`.
Reloading SketchyBar registers them again.

## One app always above another on a manual space

Without a rule, yabai puts tiled windows on sub-layer `below` and every other
window on `normal`. On a float (manual) space nothing is tiled, so an app
without a rule (Cursor, say) sat permanently above apps ruled `below` (Claude,
Yaze), whichever was focused. The yabairc now adds
`label="barista-level-base" app=".*" sub-layer=below` before any other rule,
so apps share one layer and focus decides. Rules added later still override it.
Rules reach only new windows, so at the end of startup (after the global
layout tiles the unpinned spaces) the yabairc runs
`scripts/yabai_restore.py --restack`. It moves each open standard window to
the layer its last matching rule gives it, and leaves a window raised to
`above` by hand where it is. Run it with `--dry-run` to see what it would move.

To lift or pin an app on purpose, set its Window Level: in the front-app
popup under App Defaults, in the dock's right-click menu, or with
`bin/barista app-level set <App> <normal|raised|top>`. See `window_levels` in
`docs/STATE_SCHEMA.md` for what each level maps to.

## Unified Agent & CLI API (`bin/barista`)

Agents and power users on this machine can inspect and control Barista,
SketchyBar, Yabai spaces/windows, and shortcuts through `bin/barista` (which
launches the TUI when run with no arguments, and acts as a deterministic CLI
when given a subcommand):

- **Inspection (JSON & Text):**
  - `bin/barista status --json` — live Yabai/skhd state, current space/window, active space policies, and saved counts
  - `bin/barista spaces --json` — all spaces with live layout, saved mode, UUID, lock state, and window counts
  - `bin/barista windows --json` — all windows with space, display, floating/sticky/fullscreen, layer, sub-layer, and app default
  - `bin/barista rules --json` — audit expected unmanaged rules and live window drift
  - `bin/barista shortcuts --json` — active/disabled skhd bindings, duplicates, and missing targets
  - `bin/barista stats --json` — single-pass reload and space refresh performance summary
- **Space Management & Policy Controls:**
  - `bin/barista space focus <index|prev|next|recent|first|last|app <AppName>>`
  - `bin/barista space create [--display <index|active>] [--force]`
  - `bin/barista space destroy [space] [--force]`
  - `bin/barista space layout [space] <bsp|stack|float|toggle>`
  - `bin/barista space move-left [space] | move-right [space]`
  - `bin/barista space move-display-prev [space] | move-display-next [space]`
  - `bin/barista space swap <space1> <space2> [--force]`
  - `bin/barista space lock <space-or-uuid> | unlock <space-or-uuid>`
  - `bin/barista space policy [list [--json]|get <key>|set <key> <value>]`
  - `bin/barista space prune [--dry-run]`
- **Window & App Controls:**
  - `bin/barista window <focus|swap|space|display|toggle|preset|adopt|center|minimize|close> ...`
  - `bin/barista app-default <list|set <App> <float|tile>|unset <App>|current <float|tile|unset>>`
  - `bin/barista app-level <list|set <App> <normal|raised|top>|unset <App>|current <normal|raised|top|unset>>`
  - `bin/barista state <show|get <key>|validate|restore [--dry-run]>`
  - `bin/barista reload` / `bin/barista doctor [--fix] [--probe-focus]`
