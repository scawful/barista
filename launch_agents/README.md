# Barista LaunchAgents

**Canonical location:** `~/src/lab/barista/launch_agents/`. This is the single place to edit the Barista orchestrator plist and script.

When `~/.config/sketchybar` is a symlink to `~/src/lab/barista`, the plist runs `$HOME/.config/sketchybar/launch_agents/barista-launch.sh`, which starts SketchyBar, yabai, and skhd via launchctl.

- **dev.barista.control.plist** — Install to `~/Library/LaunchAgents/` to start all three at login.
- **barista-launch.sh** — Script that starts/stops/restarts the three services. Uses `CONFIG_DIR` (default `~/.config/sketchybar`) and `helpers/launch_agent_manager.sh` from that dir.
- **dev.barista.mouse-buttons.plist** — Optional local mouse mapper for Logitech M575 middle/back/forward buttons when vendor daemons are unreliable.

**Install:** Use the install script from this repo (e.g. `bin/install_barista_agent.sh` if present) or manually copy the plist to `~/Library/LaunchAgents/` and ensure the plist’s path points to this script (when runtime is symlinked, it will).

**Alternative:** You can use `brew services start sketchybar`, `brew services start yabai`, `brew services start skhd` instead of this LaunchAgent. Document which strategy you use so syshelp/janitor assume one.

## Optional Mouse Mapper (M575)

Use `dev.barista.mouse-buttons.plist` to map mouse button events from Logitech ERGO M575:

- Button `2` (middle click) -> Mission Control
- Button `3` (back) -> `yabai -m space --focus prev`
- Button `4` (forward) -> `yabai -m space --focus next`

The LaunchAgent runs `scripts/start_mouse_button_mapper.sh` every 30 seconds.
That helper only starts a mapper when one is not already running, and starts it via Terminal so macOS input-monitoring permissions are applied consistently.

Install to `~/Library/LaunchAgents/dev.barista.mouse-buttons.plist` and bootstrap with:

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/dev.barista.mouse-buttons.plist
launchctl kickstart -k "gui/$(id -u)/dev.barista.mouse-buttons"
```

## Active Strategy (2026-02-24 CLI pass)

Use `dev.barista.control` as the orchestrator for login/startup behavior.

- Runtime path: `~/.config/sketchybar -> ~/src/lab/barista` (symlink)
- Managed labels:
  - `homebrew.mxcl.sketchybar`
  - `com.koekeishiya.yabai`
  - `com.koekeishiya.skhd`
- Do not run `brew services start sketchybar` concurrently with this orchestrator strategy.
