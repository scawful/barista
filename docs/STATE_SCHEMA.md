# Barista State Schema

`state.json` is Barista's runtime configuration file.

- Default values and migrations live in [modules/state.lua](../modules/state.lua).
- Shared read-only lookup for menus and shortcuts lives in [modules/tool_locator.lua](../modules/tool_locator.lua).
- Runtime location: `~/.config/sketchybar/state.json` or `$BARISTA_CONFIG_DIR/state.json`.

## Example

```json
{
  "profile": "personal",
  "widgets": {
    "clock": true,
    "battery": true,
    "task_focus": true
  },
  "appearance": {
    "theme": "default",
    "bar_height": 28,
    "hover_animation_duration": 8
  },
  "modes": {
    "window_manager": "optional",
    "runtime_backend": "lua",
    "widget_daemon": "auto"
  },
  "paths": {
    "scripts_dir": "/Users/you/.config/sketchybar/scripts",
    "code_dir": "/Users/you/src"
  },
  "menus": {
    "apple": {
      "show_missing": false,
      "terminal": false,
      "items": {
        "yaze": { "enabled": true }
      }
    },
    "oracle": {
      "sections": {
        "play": { "enabled": true }
      },
      "triforce": {
        "label": "",
        "icon": ""
      }
    },
    "apps": {
      "enabled": true,
      "file": "data/project_shortcuts.json",
      "default_action": "terminal"
    },
    "work": {
      "workspace_domain": "example.com"
    },
    "calendar": {
      "task_provider": "files",
      "task_sources": ["/path/to/tasks.md"]
    },
    "extensions": {
      "enabled": true,
      "file": "data/interface_extensions.local.json",
      "files": [],
      "packs": []
    }
  },
  "integrations": {
    "yaze": { "enabled": true }
  }
}
```

## Top-Level Keys

| Key | Type | Purpose |
|-----|------|---------|
| `_version` | number | State schema version used by migrations. |
| `profile` | string | Active profile name (`minimal`, `cozy`, `work`, `personal`). |
| `widgets` | object | Per-widget enable/disable flags. |
| `appearance` | object | Bar, popup, font, hover, and grouping appearance settings. |
| `icons` | object | Named icon overrides such as `apple`, `wifi`, `volume`. |
| `widget_colors` | object | Per-widget color overrides. |
| `space_icons` | object | Custom icon per space number. |
| `space_modes` | object | Numeric compatibility mirror for saved space layouts (`bsp`, `stack`, or `float`). |
| `space_modes_by_uuid` | object | Canonical saved layouts keyed by the macOS space UUID. |
| `space_mode_uuids` | object | Binds numeric compatibility entries to UUIDs so replay does not apply them twice. |
| `spaces` | object | Space-management behavior toggles. |
| `system_info_items` | object | Controls which system-info popup rows are shown. |
| `modes` | object | Runtime mode switches such as window manager and backend selection. |
| `toggles` | object | Persisted toggles (`yabai_shortcuts`, `stack_indicator`). |
| `workflow` | object | Settings for scratchpads, Emacs client commands, and the file picker. |
| `paths` | object | Runtime path overrides. |
| `menus` | object | Apple-menu popup sections, app shortcuts, and web-app shortcut configuration. |
| `integrations` | object | Per-integration enablement and metadata. |
| `machine` | object | Machine-local profile variant summary written by `scripts/machine_profile.py`. |

## Important Nested Keys

### `widgets`

Common keys:

- `agents`
- `clock`
- `system_info`
- `volume`
- `battery`
- `network`
- `task_focus`

`agents` controls the right-side agent manager (running Codex/Claude/Cursor/Gemini
sessions, Codex usage, and the LM Studio `Local` submenu). It has no state
default, so the profile decides: Personal enables it; minimal, cozy, work, and
restricted variants disable it.

`task_focus` is kept as the machine's task opt-in flag. Work and restricted
variants force it to `false` along with clearing task sources. No bar chip
reads it anymore; task rows live in the clock popup.

### `system_info_items`

The dynamic-row keys are `cpu`, `mem`, `disk`, `net`, `swap`, `uptime`, and
`procs`. They independently control both popup topology and the bounded helper
allowlist. `actions` defaults to `true`; setting it to `false` preserves the
enabled metrics, leaves Top CPU visible but non-clickable, and omits the Activity
Monitor and System Settings launchers. The legacy `docs` key is retained for
state compatibility but no longer creates rows; workflow documentation lives in
the Apple menu and Help Center.

### `appearance`

Common keys:

- `theme`
- `bar_height`
- `widget_scale`
- `auto_more_space_scaling`
- `more_space_widget_scale_boost`
- `menu_item_height`, `menu_header_height`, `menu_padding`
- `menu_item_corner_radius`, `menu_font_style`, `menu_header_font_style`, `menu_font_size_offset`
- `bar_padding_left`, `bar_padding_right`, `bar_margin`, `bar_y_offset`
- `corner_radius`, `bar_corners` (`all`, `top`, `bottom`, `none`), `bar_color`, `blur_radius`
- `group_bg_color`, `group_border_color`, `group_border_width`, `group_corner_radius`
- `native_hover` (`auto` default, `on`, `off`)
- `widget_corners`, `popup_corners` (`all`, `top`, `bottom` default, `none`)
- `widget_hover_color`, `widget_hover_border_color`, `widget_border_width`
- `menu_separator_color` (popup header and separator hairlines; falls back to `popup_border_color`)
- `popup_padding`, `popup_corner_radius`, `popup_border_width`, `popup_border_color`, `popup_bg_color`
- `popup_blur_radius`, `popup_shadow` (native window shadow), `popup_icon_width` (fixed icon column for single-glyph popup rows)
- `hover_color`, `hover_border_color`, `hover_animation_curve`, `hover_animation_duration`
- `submenu_hover_color`, `submenu_idle_color`, `submenu_close_delay`
- `submenu_hover_corner_radius`, `submenu_hover_padding_left`, `submenu_hover_padding_right`
- `font_icon`, `font_text`, `font_numbers`, `font_popup` (popup row text; numeric rows keep `font_numbers`)

`widget_scale` is the manual baseline. When `auto_more_space_scaling` is enabled, Barista detects a built-in display running a downscaled macOS "More Space" mode, raises the effective bar height to match the top inset when needed, and adds `more_space_widget_scale_boost` on top of the widget baseline.

When `auto_display_density` is enabled (default), Barista measures every SketchyBar display's logical width and classifies each as wide or narrow/portrait:

- **Split layouts** (laptop + portrait external): the wide desktop keeps the full widget set, labels, and clock. Optional/heavy widgets (`music_studio`, `agents`, `system_info`) and the full clock/volume/battery stay on wide displays. Narrow monitors get compact `clock_narrow` / `volume_narrow` / `battery_narrow` clones plus the usual spaces strip.
- **All-narrow** (only a portrait/small display): global compact/dense chrome applies (`comfortable` / `compact` / `dense` by min width).
- Display add/remove/rotate events recompute a density fingerprint (`plugins/display_density.sh`) and reload SketchyBar only when the mode changes.

`native_hover` selects the Barista SketchyBar fork features. With `auto`,
`main.lua` runs `sketchybar --query defaults` once at load: a `hover_color` key
turns on native hover and a `popup.stretch` key turns on full-width popup rows.
Stock SketchyBar answers with neither, so `auto` keeps the script hover and
content-width rows there. With native hover:

- the fork draws `widget_hover_color` and `widget_hover_border_color` under the
  pointer, so widgets need no hover event script;
- `widget_corners` and `popup_corners` round only the chosen corners;
- left widgets (Triforce, music, control center, agents) share one `left_group`
  bracket and right widgets share one `right_group` bracket, filled with
  `group_bg_color`; each grouped widget draws only an inset hover highlight;
- the spaces keep their own chips, and so does the front app chip when
  `spaces.merge_front_app` is `false`;
- popups set `popup.stretch=on`, and separators and headers draw as
  `menu_separator_color` hairlines.

`main.lua` writes `cache/native_hover` (`1` or `0`) and `cache/chip_style`
(`<height> <corner_radius> <corners>`) so shell plugins such as
`plugins/simple_spaces.sh` style space chips without querying SketchyBar.

Menu popup rows are separate from the bar now: `menu_item_height`, `menu_header_height`, and `menu_padding` control popup density without changing the bar height.

`hover_animation_duration` uses whole frames at 60 Hz (default `8`, about
133 ms). `0` selects immediate popup-row, anchor, and space-creation highlights,
including the fast Triforce path. Negative values become `0`; fractional values round down;
invalid or non-finite values use `8`. Space selection and submenu visibility
keep their existing event behavior.

On a DisplayLink or other multi-monitor setup, an optional lower-effects
configuration is `"blur_radius": 0` and `"hover_animation_duration": 0` inside
`appearance`. These are explicit per-machine choices; Barista does not infer
connection type from monitor names or disable effects automatically. Merge
these keys into the existing local file, then use
`./plugins/reload_sketchybar.sh`. Restore your prior values to undo the change.

`bar_corners` picks which corners `corner_radius` rounds. `"bottom"` keeps the
bar flush with the top edge and rounds only the lower corners. Values other than
`all` need the Barista SketchyBar fork (`sketchybar --bar corners=bottom`);
`all` is the default and is never sent, so stock SketchyBar keeps working. The
bar blur covers the whole window rectangle, so on a busy wallpaper a faint
blurred square can show outside a rounded corner; `"blur_radius": 0` removes it.

Barista's normal top placement keeps `bar_y_offset` explicit. The live default
is `0`; do not introduce implicit offset behavior when debugging popup clicks.

Barista uses two menu terms deliberately:

- `popup section` means a grouped block of rows inside a popup.
- `legacy fly-out submenu` means a nested hover-open popup attached to a row.

See [GLOSSARY.md](GLOSSARY.md) for the short version.

The full default set is defined in [modules/state.lua](../modules/state.lua).

### `modes`

Supported keys:

- `window_manager`: `disabled`, `optional`, `required`, or `auto`
- `runtime_backend`: `lua`, `compiled`, or `auto`
- `widget_daemon`: `auto`, `enabled`, or `disabled`

Restricted work-laptop setup writes `window_manager = "disabled"`,
`runtime_backend = "lua"`, and `widget_daemon = "disabled"` so Barista avoids
yabai/skhd and compiled helper paths.

### Saved space layouts and startup

`plugins/set_space_mode.sh` queries and validates a live space, applies its
layout, verifies it, and saves the UUID plus numeric compatibility entry using
`scripts/yabai_state.py`. Manual (`float`) is an explicit preference. It is not
represented by deleting the entry.

`space_modes_by_uuid` is authoritative after a desktop reorder. A missing UUID
is skipped; its old index is never used as a fallback. Legacy numeric entries
without a UUID binding remain supported until that layout is saved again.
`scripts/yabai_restore.py --dry-run` shows the proposed startup actions without
changing anything. `bin/barista space prune` (or `scripts/yabai_control.sh space-prune`)
prunes orphaned UUIDs from `space_modes_by_uuid` and remaps moved live UUIDs to
their current numeric space indices.

### `spaces` policy & restrictions

Supported keys under `spaces`:

- `creator_mode`: `per_display` (default), `primary`, or `active`
- `right_click_close`: `confirm` (default), `direct`, or `off`
- `reorder_mode`: `menu` (default), `modifier_click`, or `off`
- `merge_front_app`: `true` (default) hides the separate front app chip; a click on the already-active space chip opens the front app menu under that chip. `false` restores the front app chip.
- `max_spaces_per_display`: maximum spaces allowed per display (`8` default; `0` = unlimited)
- `min_spaces_per_display`: minimum spaces preserved per display (`1` default)
- `destroy_non_empty_policy`: `allow` (default), `refuse` (blocks destroying spaces with windows), or `evacuate` (moves windows to an alternate space on the same display before destroying)
- `new_space_layout`: `default` (default), `bsp`, `stack`, `float`, or `inherit` (applies and persists the chosen layout when creating a space)
- `window_move_policy`: `preserve` (default; keeps manual floating across spaces unless entering a floating space) or `adopt_destination` (adopts destination space layout)
- `locked_spaces`: map or array of space indices/UUIDs protected from destruction, reordering, and layout overwrites unless `--force` (`BARISTA_SPACE_FORCE=1`) is passed

The yabairc uses `--startup` after base/custom app rules: saved app rules are
installed first, saved layouts are pinned with `config --space ... layout`,
and the global Tile default is applied afterward. Matching Manual layouts must
also be pinned to prevent the global default from briefly tiling them.
Visual refresh only renders observed layout; focusing a space does not reapply
saved preferences.

The startup supervisor starts eligible installed services in Yabai, skhd,
SketchyBar order. `auto` starts installed Yabai; `required` reports missing
services; `optional` leaves Yabai startup to its existing service; `disabled`
skips Yabai and skhd. These choices do not stop an already running service or
disable independently enabled LaunchAgents. `toggles.yabai_shortcuts=false`
skips skhd. The shortcut Off action also disables its selected LaunchAgent so
that the preference survives login; On enables that same service. Shortcut
status is read-only.

### `toggles` and `workflow`

Toggles under `toggles` (TUI Advanced tab):

- `yabai_shortcuts` (`true` default): skhd shortcut management. Change it with
  `scripts/toggle_shortcuts.sh`, which also updates the skhd service.
- `stack_indicator` (`true` default): show an `[idx/total]` badge on
  `front_app` for a stacked window. Also `barista feature stack_indicator [on|off|toggle]`.

Settings under `workflow` (`barista workflow [list|get <key>|set <key> <value>]`),
used by `scripts/barista_workflow.sh`:

- `scratchpad.width_pct` / `scratchpad.height_pct` (`75` default, `25..100`)
- `scratchpad.terminal_cmd` (`""` default), `scratchpad.files_cmd` (`"yazi"`)
- `emacs.client_bin` (`"emacsclient"`), `emacs.app_name` (`"Emacs"`), `emacs.capture_key` (`""`)
- `files.picker` (`"auto"`, `"yazi"`, `"fzf"`, or `"dired"`), `files.default_root` (`"~/src"`)

These commands have no global hotkeys. Bind them in your own skhdrc or load
`extras/skhd/barista_submaps.conf` for leader submaps.

### `window_defaults`

Supported keys:

- `apps.<App Name>.mode`: `float` or `tile`
- `apps.<App Name>.app_regex`: exact app regex installed as a yabai rule
- `apps.<App Name>.rule_label`: stable `barista-default-*` yabai rule label
- `apps.<App Name>.manage`: the rule field Barista writes

These entries are written by `scripts/yabai_control.sh app-default ...` and by
the app-icon App Defaults popup rows. `float` means unmanaged/manual
(`manage=off`); `tile` means managed by yabai (`manage=on`). Neither sets a
sub-layer: stacking belongs to `window_levels`. Unsetting an app removes the
persisted state and verifies removal of the matching live yabai rule label.
Saved Barista defaults are replayed after base app rules on Yabai startup.
Other rules remain in force.

### `window_levels`

Where every window of an app stacks, by app name:

- `<App Name>.level`: `normal`, `raised`, or `top`
- `<App Name>.app_regex`: exact app regex installed as a yabai rule
- `<App Name>.rule_label`: stable `barista-level-*` yabai rule label

| Level | yabai sub-layer | Meaning |
|-------|-----------------|---------|
| `normal` | `below` | Shared with tiled windows and every app without a level; focus decides |
| `raised` | `normal` | Above every `normal` window, tiled or floating |
| `top` | `above` | Always on top |

The yabairc base rule `barista-level-base` puts every app on `below` first, so
no app without a rule sits permanently above the others on a float (manual)
space. Entries are written by `scripts/yabai_control.sh app-level ...`, the
front-app popup's Window Level rows, and the dock's Window Level menu. Setting
a level also moves the app's open standard windows. Levels are replayed after
`window_defaults` on Yabai startup, so they override the yabairc stacking rules.
`unset` removes the entry and the rule, and the app's windows go back to what
the yabairc rules give them.

### `machine`

Supported keys written by `scripts/machine_profile.py`:

- `profile_variant`: one of `minimal`, `cozy`, `personal`, `work`, or `restricted-work`
- `restricted`: whether this machine should avoid native apps, compiled helpers, yabai, and skhd
- `menu_packs`: logical menu groups enabled for this machine
- `allowed_features`: capability-gated booleans such as `native_panel`, `compiled_helpers`, `window_manager`, and `work_apps`

The detailed capability snapshot is stored in `data/machine.local.json`, which
is intentionally gitignored. `state.machine` keeps only the runtime summary that
the bar and tools can read cheaply.

### `paths`

Common supported keys:

- `scripts_dir`
- `code_dir` or `code`

`tool_locator.lua` prefers explicit runtime context first, then env vars, then persisted path overrides, then built-in defaults.

### `menus.apple`

Supported keys used by the Apple menu:

- `show_missing`
- `terminal`
- `launch`
- `items.<id>.enabled`
- `items.<id>.label`
- `items.<id>.icon`
- `items.<id>.icon_color`
- `items.<id>.label_color`
- `items.<id>.order`
- `custom[]`
- `custom[].items[]`
- `hover.color`
- `hover.border_color`
- `hover.border_width`
- `sections.<section_id>.label`
- `sections.<section_id>.icon`
- `sections.<section_id>.color`
- `sections.<section_id>.order`

This config controls Apple-menu popup sections. Legacy fly-out submenu behavior is driven mostly by `appearance.submenu_*`.

Each `menus.apple.custom[]` entry can be either:

- a single action row with `label`, `command`/`action`, optional `icon`, `shortcut`, and `section`
- a nested fly-out group with `items[]`

Nested `items[]` rows support:

- `type = "header"`
- `type = "separator"`
- standard rows with `label`, `command`/`action`, `url`, `icon`, `shortcut`, and optional nested `items[]`

### `menus.calendar`

Supported keys used by the calendar popup:

- `task_provider`: `files` or `syshelp` (`files` by default)
- `task_sources`: string or array of local Markdown/Org task files
- `meeting_cache_file`: optional local `events.tsv` cache for one next-meeting row
- `meeting_cache_max_age_seconds`: positive cache freshness limit (`86400`, or 24 hours, by default)
- `syshelp_path`: optional absolute `syshelp` executable path for launchd environments
- `capture_section`: optional syshelp capture section (`Active` by default)
- `capture_state`: optional syshelp capture state (`TODO` by default)

Committed defaults use `task_provider="files"` and an empty `task_sources`
array. Configure personal and work boards only in ignored `state.json` or
`barista_config.lua`. Applying the `work` or `restricted-work` machine variant
resets the provider to `files`, clears all task sources, and disables
`widgets.task_focus` as a privacy boundary.

The `files` provider parses configured Markdown checkboxes and Org task
headings, including explicit `NEXT`, `WAITING`, and `BLOCKED` states. It is
read-only: `Capture Task` opens the first configured board rather than guessing
how to mutate an arbitrary file. The `syshelp` provider requires the local
`syshelp` command, reads `syshelp plan tasks json`, and captures through
`syshelp plan tasks add` using `capture_section` and `capture_state`. Set
machine-local `syshelp_path` when launchd's reduced `PATH` cannot find the
executable; do not commit a user-specific absolute path.

The clock popup keeps status-only `Focus`, `Next`, `Waiting`, and `Blocked`
rows. It refreshes when opened and does not poll while closed.
Focus-session state is local under ignored
`cache/focus_session/state.json`; it creates no additional bar widget or daemon.
Successful syshelp capture emits `task_state_changed`, and external task tools
can trigger the same event so the optional chip can refresh without a timer.

`meeting_cache_file` is read-only and opt-in. When configured, the clock popup
shows at most one bounded cached event containing only its time and title. The
row stays hidden when the path is unset, missing, invalid, older than
`meeting_cache_max_age_seconds`, larger than 1 MiB, or has no future events. The TSV header must
contain `start_date`, `start_time`, and `title`; dates use `YYYY-MM-DD`, times
use `HH:MM`/`HH:MM:SS` or 12-hour `H:MM AM`, and all-day rows keep an empty
`start_time`. Additional fields such as location, description, and calendar are
ignored and never rendered. Barista never starts calendar authentication,
syncing, or network work; an external owner such as `syshelp calendar sync`
must write the TSV cache. Work and restricted-work setup clear this
machine-local path.

Schema v2 migrates the former bundled personal source pair conservatively. It
clears that exact unmodified list only on a non-Personal profile with no task or
meeting opt-in markers. Personal profiles, custom source lists, and explicit
task configuration remain unchanged.

### `menus.extensions`

Supported keys:

- `enabled`
- `file`
- `files[]`
- `packs[]`
- `items[]`

Interface extensions are script-backed rows for `apple_menu`, `front_app`,
`control_center`, and `lmstudio` surfaces. The default file is
`data/interface_extensions.local.json`, which is gitignored. See
[guides/INTERFACE_EXTENSIONS.md](guides/INTERFACE_EXTENSIONS.md).

### `menus.oracle`

Supported keys:

- `sections.<section_id>.enabled`
- `sections.<section_id>.label`
- `sections.<section_id>.order`
- `sections.<section_id>.limit`
- `triforce.label`
- `triforce.icon`
- `triforce.title`
- `triforce.show_label`

Known section ids:

- `play`

This config drives the standalone Zelda hacking surface:

- the left-bar `Triforce` widget popup
- the native Barista control-panel `Zelda` tab as its status source

Section visibility and ordering shape the shallow Triforce popup. In the current design, `play` has two rows: launch the stable ROM (the highest `Roms/oosNNNx.sfc`) or the newest test build (`Roms/TestBuilds/*/oosNNNx.sfc`) through `Scripts/Build/oos-triforce.sh launch stable|test`. The native Zelda tab owns the deeper workflow detail.

Triforce status is event-driven: it refreshes after configuration, on anchor
click, and after wake. There is no configurable polling interval.
Normalization prunes the retired `triforce.update_freq` key from older state.

Notes:

- `menus.oracle` still configures the bar-facing Zelda surface, not the full native panel layout.
- Oracle Hub owns the deeper status view backed by
  `Scripts/Debug/oos_status.py`; Barista does not add separate persisted task
  state for that workflow.
- Oracle status items like `today`, `next`, and `blocked` still exist in the status snapshot for the native panel, but they no longer create nested Triforce popup sections.
- `open_control_panel.sh --oracle` forwards to Oracle Hub.

### `menus.apps`

Supported keys:

- `enabled`
- `file`
- `default_action`
- `items[]`

`file` usually points at `data/project_shortcuts.json`, which stores generic app shortcut rows for the `Apps` popup section. The committed default is intentionally empty; machine-local launchers should use `menus.extensions`.

Each app shortcut item can define:

- `id`
- `label`
- `path`
- `icon`
- `icon_color`
- `label_color`
- `order`
- `section`
- `shortcut`
- `open_mode` (`terminal`, `finder`, or `code`)
- `action` (explicit shell command override)

`menus.projects` is still supported as a legacy alias and is merged into `menus.apps` automatically.

### `menus.work`

Supported keys:

- `google_apps`
- `apps_file`
- `workspace_domain`

These render as web-app shortcuts inside a popup section. The historical state key is still `google_apps`, but the UI now labels them `Web App Shortcuts`.

`scripts/restricted_config.py` and `scripts/configure_work_google_apps.sh` can
write this section without `jq` or the native control panel. By default they
write the JSON array to `data/work_apps.local.json` relative to `state.json`.

### `integrations`

Each integration entry is a free-form object.

Barista currently expects an `enabled` boolean for feature gating, for example:

```json
{
  "integrations": {
    "yaze": { "enabled": true },
    "oracle": { "enabled": false }
  }
}
```

Known integration-specific keys used by the active runtime:

- `integrations.control_center.enabled`
- `integrations.control_center.item_name`
- `integrations.control_center.show_label` (default `false`; icon only)

`integrations.control_center.item_name` is optional. When set, Barista uses it as
the shared item name for:

- the left-bar control-center widget
- popup-parent registration and dismissal
- helper popup attachment that targets the control center
- the generated `toggle_control_center` shortcut command

The Work profile leaves `halext`, `halext_org`, and `workspace` disabled by
default. Enable only the integration a particular work Mac actually provides
through its ignored local state or `barista_config.lua`; they are not portable
Work prerequisites.

## Notes

- GUI and TUI tools write to `state.json`; `barista_config.lua` is the right place for machine-specific overrides you do not want overwritten.
- If you add new persisted keys, update both [modules/state.lua](../modules/state.lua) defaults and this document.
