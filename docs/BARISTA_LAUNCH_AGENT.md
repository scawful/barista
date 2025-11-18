# Barista Launch Agent — Draft Specification

## Purpose
Provide a single LaunchAgent that orchestrates SketchyBar, Yabai, and skhd for Barista users. The agent should:

1. Start/stop all bar-related daemons deterministically (no race conditions, no stale lock files).
2. Offer a CLI surface (`launch_agent_manager.sh` + `barista-launch.sh`) so GUI, Lua menus, and scripts use the same entry points.
3. Support future health checks and self-healing routines (automatic restarts, diagnostics, AI hooks).

## Components
| File | Description |
|------|-------------|
| `launch_agents/barista-launch.sh` | Orchestrator that issues `start`, `stop`, `restart` commands for SketchyBar, Yabai, and skhd via `helpers/launch_agent_manager.sh` (with launchctl fallback). |
| `launch_agents/dev.barista.control.plist` | Sample LaunchAgent definition targeting `~/Library/LaunchAgents`. Runs the orchestrator with `start` on load and `stop` on unload. |
| `helpers/launch_agent_manager.sh` | Shared helper (already implemented) that lists/manages any GUI-domain LaunchAgent. |

## Proposed Flow
1. **Startup**:
   - `launchctl load ~/Library/LaunchAgents/dev.barista.control.plist`
   - LaunchAgent executes `barista-launch.sh start`.
   - Orchestrator restarts `homebrew.mxcl.sketchybar`, `org.nbirrell.yabai`, and `org.nbirrell.skhd` (labels overridable via env).
2. **Shutdown**:
   - `launchctl unload ...` triggers `barista-launch.sh stop`.
   - Script gracefully stops agents to avoid zombie processes.
3. **Manual Control**:
   - Users/GUI call `barista-launch.sh restart sketchybar` or the generic `helpers/launch_agent_manager.sh` interface.

## Configuration
Environment variables understood by `barista-launch.sh`:
- `BARISTA_SKETCHYBAR_LABEL` (default `homebrew.mxcl.sketchybar`)
- `BARISTA_YABAI_LABEL` (default `org.nbirrell.yabai`)
- `BARISTA_SKHD_LABEL` (default `org.nbirrell.skhd`)
- `BARISTA_AGENT_HELPER` (default `~/.config/sketchybar/helpers/launch_agent_manager.sh`)

## Usage (Draft)
```bash
# Copy plist to LaunchAgents
~/.config/sketchybar/bin/install_barista_agent.sh   # copies files + restarts

# (manual alternative)
cp launch_agents/dev.barista.control.plist ~/Library/LaunchAgents/

# Load the agent
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.barista.control.plist

# Check status
~/.config/sketchybar/helpers/launch_agent_manager.sh status dev.barista.control
```

## Roadmap
- Health monitoring: tail logs, detect crashes, auto-retry with backoff.
- IPC bridge: expose current state via JSON for AI/autonomous workflows.
- Install script: `bin/install_barista_agent.sh` to copy plist, set permissions, and load automatically.
- Add helper integration in menus/GUI to run `install_barista_agent.sh` for first-time setup.
- Integration with GUI Launch Agents tab (start/stop Barista supervisor, not just individual daemons).

> **Note**: The plist + script included here are prototypes; they are not loaded by default. Users must copy them into `~/Library/LaunchAgents` and opt in.

