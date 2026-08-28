# Barista LaunchAgents

Templates live in this directory. They contain portable defaults; the installer
renders machine-specific absolute paths into `~/Library/LaunchAgents`.

The control agent runs the `barista-launch.sh` from the selected runtime and
starts SketchyBar, yabai, and skhd through launchctl.

- **dev.barista.control.plist** — Install to `~/Library/LaunchAgents/` to start all three at login.
- **barista-launch.sh** — Script that starts/stops/restarts the three services. Uses `BARISTA_CONFIG_DIR` (default `${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar`) and `helpers/launch_agent_manager.sh` from that dir.
- **dev.barista.mouse-buttons.plist** — Optional local mouse mapper for Logitech M575 middle/back/forward buttons when vendor daemons are unreliable.

**Install:**

```bash
./bin/install-launch-agent --config-dir "${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
./bin/install-launch-agent \
  --config-dir /path/to/barista-runtime \
  --code-dir /path/to/company/source \
  --bin-dir /path/to/company/bin
```

Use `--dry-run`, `--no-start`, or `--mouse-buttons` as needed. Existing plists
are backed up before replacement. `--code-dir` and repeatable `--bin-dir`
values are rendered into the LaunchAgent environment so login startup does not
depend on an interactive shell profile.

**Alternative:** You can use `brew services start sketchybar`, `brew services start yabai`, `brew services start skhd` instead of this LaunchAgent. Document which strategy you use so syshelp/janitor assume one.

## Optional Mouse Mapper (M575)

Use `dev.barista.mouse-buttons.plist` to map mouse button events from Logitech ERGO M575:

- Button `2` (middle click) -> Mission Control
- Button `3` (back) -> `yabai -m space --focus prev`
- Button `4` (forward) -> `yabai -m space --focus next`

The LaunchAgent runs `scripts/start_mouse_button_mapper.sh` every 30 seconds.
That helper only starts a mapper when one is not already running, and starts it via Terminal so macOS input-monitoring permissions are applied consistently.

Install and bootstrap it with:

```bash
./bin/install-launch-agent --mouse-buttons
```

## Service ownership

Use `dev.barista.control` as the orchestrator for login/startup behavior.

- Managed labels:
  - `homebrew.mxcl.sketchybar`
  - `com.asmvik.yabai` (the supervisor falls back to
    `com.koekeishiya.yabai` when the current plist is absent)
  - `com.koekeishiya.skhd`
- Do not run `brew services start sketchybar` concurrently with this orchestrator strategy.

`dev.barista.control` is intentionally a one-shot supervisor: it starts or
kickstarts those three long-running agents and then exits. Seeing the supervisor
as `not running` with last exit status `0` is healthy when all three managed
labels are running.
