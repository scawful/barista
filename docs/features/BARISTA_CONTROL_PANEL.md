# Barista Settings — Vision & Roadmap

## Mission
Transform the former “SketchyBar control panel” into a Barista-branded control surface for power users. The panel should manage menu bar widgets, launch agents, developer tooling, and (eventually) AI-assisted workflows from one place.

## Pillars
1. **Universal Access** – GUI tabs, Lua menus, CLI wrappers, and skhd/btt shortcuts all hit the same helpers.
2. **Safe Automations** – Prefer `launchctl kickstart/gui` over ad-hoc reloads; fall back to bootstrap when necessary.
3. **Debuggable Everything** – Toggle logging, hotload, rebuild/reload macros, and capture diagnostics without leaving the panel.
4. **AI-Ready** – Expose structured data (JSON helpers, doc links, prompt templates) so future agents can reason about state.

## Feature Overview
| Area | Status | Notes |
|------|--------|-------|
| Launch Agents tab | 🚧 | Lists `~/Library/LaunchAgents`, shows `launchctl list` output, start/stop/restart via helper |
| Debug tab | 🚧 | Verbose logging, hotload enable/disable, widget refresh interval, cache flush actions |
| Global shortcuts | 🚧 | `bin/rebuild_sketchybar.sh`, `bin/open_control_panel.sh`, future “toggle popups” + “run diagnostics” |
| Control-center menu | ✅ base | Consolidated Apple/front-app menu; needs Launch Agent + Debug submenus |
| AI hooks | ⚙️ design | Surfaced via doc links + future Ollama/OpenAI integrations |

## Launch-Agent Management
- Helper: `helpers/launch_agent_manager.sh` (planned)
  - `list` → JSON array with name, label, plist path, pid/status.
  - `start <label>` → `launchctl kickstart -k gui/$UID/<label>` (fallback to `launchctl bootstrap`).
  - `stop <label>` → `launchctl bootout gui/$UID/<label>`.
  - `restart` → stop + start with debounced delays.
- GUI Tab:
  - Table view with filtering, search, per-agent controls.
  - Status badges (Running, Sleeping, Failed).
  - Batch actions (“Restart All Barista agents”).

## Debug & Diagnostics
- Toggles for:
  - `menu_action` highlight color + reset delay.
  - SketchyBar hotloader (`sketchybar --hotload on/off`).
  - Widget refresh intervals.
- Buttons:
  - “Rebuild & Reload SketchyBar” (calls `bin/rebuild_sketchybar.sh`).
  - “Open Logs” (wraps `~/.config/sketchybar/scripts/bar_logs.sh`).
  - “Flush icon cache”, “Reset popup state”.

## Shortcuts & CLI Wrappers
- `bin/rebuild_sketchybar.sh`
  1. `make -C helpers all`
  2. `make -C gui all`
  3. `~/.config/sketchybar/scripts/launch_agents.sh reload sketchybar` (placeholder)
- `bin/open_control_panel.sh`
  - Launches the preferred control panel (native Cocoa by default).
  - Routing is configured via `control_panel.preferred` in state.json or env vars (see below).

Help Center + Barista metadata lives in:
- `data/workflow_shortcuts.json` (keymap, docs, quick actions)
- `data/menu_help.json` (Help menu entries)
- Regenerate `~/.config/skhd/barista_shortcuts.conf` with `BARISTA_CONFIG_DIR=/path/to/barista lua helpers/generate_shortcuts.lua` after shortcut changes.
- Future:
  - `bin/toggle_popups.sh`
  - `bin/launch_agent <label> <action>`
  - `skhd` bindings for rebuilding, opening panels, toggling debug overlays.

## Local Workflow Launcher

The native Home and Integrations tabs call `scripts/open_local_workflow.sh` for machine-local exits. Keep local path resolution in that script rather than duplicating hard-coded repo/app paths in Objective-C views.

Current launch targets include Ghostty, LM Studio/status, AFS Studio/context/repo, scawfulbot, Yaze/z3ed, Loom Studio, premia, halext-org, and the Barista repo.

## Native Settings UX

- The Cocoa panel opens to Home by default when there is no saved tab, so the menu entry lands on a routing surface instead of a single settings form.
- The default window mode is `standard`; yabai rules keep the settings panel unmanaged without making it a topmost utility window.
- Settings chrome uses AppKit semantic colors and the system UI font. The active SketchyBar theme is only used as an accent where it helps orientation.
- Monospace stays reserved for code/config previews.
- The sidebar avoids Nerd Font-only glyphs; missing icon boxes make the panel feel broken on machines without the same font stack.
- Local workflow actions report launch status inline. Avoid modal alerts for successful exits to external tools.

## Barista App Routing

Barista supports multiple UIs without deleting legacy implementations.

### Stable native app bundle

The native Cocoa panel is installed to:

```
~/Applications/Barista.app
```

`bin/open_control_panel.sh` prefers that stable app bundle when it is present. If a newer build exists at `build/bin/Barista.app`, the launcher attempts to refresh the stable bundle before opening it. Legacy `BaristaControlPanel.app` artifacts remain supported as fallbacks during migration.

To install or refresh the bundle without launching it:

```
scripts/install_control_panel_app.sh
```

### Preferred panel (state.json)

```
control_panel.preferred = "native" | "imgui" | "custom"
control_panel.command = "open -a MySwiftUIApp"
```

- `native`: Cocoa-based `config_menu` (default).
- `imgui`: `barista_config` (ImGui) if present.
- `tui`: Python TUI (`bin/barista`) when native GUI isn’t available.
- `custom`: run the command specified in `control_panel.command`.

When `modes.runtime_backend = "lua"` or `BARISTA_RESTRICTED_MODE=1`, a missing
TUI stops at the manual `state.json` / docs fallback instead of trying to build
or launch the native Cocoa panel. This keeps managed work laptops out of the
compiled-app approval path.

### Env overrides

- `BARISTA_CONTROL_PANEL` or `BARISTA_CONTROL_PANEL_MODE`
- `BARISTA_CONTROL_PANEL_CMD`
- `BARISTA_IMGUI_BIN`
- `BARISTA_TUI_ONLY` (force TUI fallback)

### CLI flags

```
bin/open_control_panel.sh --native
bin/open_control_panel.sh --imgui
bin/open_control_panel.sh --tui
bin/open_control_panel.sh --custom --command "open -a MySwiftUIApp"
```

## Barista Launch Agent (Concept)
- Goal: single plist (e.g., `~/Library/LaunchAgents/dev.barista.control.plist`) that bootstraps:
  - `sketchybar --config ~/.config/sketchybar/sketchybarrc`
  - `yabai --config ~/.config/yabai/yabairc`
  - `skhd --config ~/.config/skhd/skhdrc`
  - Health-check daemon (optional) that restarts components via the launcher helper.
- Managed by the Launch Agents tab once implemented.

## Roadmap (Short Term)
1. Ship doc refresh (this file, `MIGRATION_NOTES.md`, updated improvements section). ✅
2. Implement `helpers/launch_agent_manager.sh` + CLI wrappers. 🚧
3. Add Launch Agents + Debug tabs in `gui/config_menu_enhanced.m`. 🚧
4. Surface actions/shortcuts inside `modules/menu.lua` + `modules/shortcuts.lua`. 🚧
5. Draft `docs/BARISTA_LAUNCH_AGENT.md` with plist prototype + orchestrator script. 🚧

## Roadmap (Future)
- AI assistant integration (Ollama + remote providers) with one-click prompts.
- Workspace presets (profiles) that reconfigure launch agents, widgets, and shortcuts together.
- Telemetry opt-in for tracking performance regressions and automated bug reports.
