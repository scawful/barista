# Barista Control Panel — Vision & Roadmap

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
- Future:
  - `bin/toggle_popups.sh`
  - `bin/launch_agent <label> <action>`
  - `skhd` bindings for rebuilding, opening panels, toggling debug overlays.

## Control Panel Routing

Barista supports multiple UIs without deleting legacy implementations.

### Preferred panel (state.json)

```
control_panel.preferred = "native" | "imgui" | "custom"
control_panel.command = "open -a MySwiftUIApp"
```

- `native`: Cocoa-based `config_menu` (default).
- `imgui`: `barista_config` (ImGui) if present.
- `custom`: run the command specified in `control_panel.command`.

### Env overrides

- `BARISTA_CONTROL_PANEL` or `BARISTA_CONTROL_PANEL_MODE`
- `BARISTA_CONTROL_PANEL_CMD`
- `BARISTA_IMGUI_BIN`

### CLI flags

```
bin/open_control_panel.sh --native
bin/open_control_panel.sh --imgui
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
