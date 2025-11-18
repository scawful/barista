# Sketchybar Migration Notes

This document outlines the current state of the `sketchybar` configuration and a potential migration scenario.

## Current Setup:

1.  **`~/.config/sketchybar`**: This directory is currently a symbolic link pointing to `~/Code/sketchybar`. This means the active `sketchybar` configuration is loaded from `~/Code/sketchybar`.

2.  **`~/Code/sketchybar` Repository**:
    *   This repository contains a `sketchybar` configuration.
    *   A recent `git status` showed a large number of deleted and modified files, along with a few untracked files. This indicates that a significant cleanup or migration of this configuration is either in progress or has recently occurred.
    *   A script (`stage_changes.sh`) was run to stage these changes for review and commit.

3.  **`~/Code/barista` Repository**:
    *   This repository was recently cloned and appears to contain a complete and new `sketchybar` configuration. Its structure (e.g., `main.lua`, `plugins`, `themes`) suggests it is intended to be a functional `sketchybar` setup.

4.  **`sketchybar` Launch Agent**:
    *   The `launchd` agent responsible for starting `sketchybar` is `~/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist`.
    *   This agent is configured to run the `sketchybar` executable installed via Homebrew (specifically, `/opt/homebrew/opt/sketchybar/bin/sketchybar`).
    *   This executable then loads its configuration from the path specified by `~/.config/sketchybar`.

## Potential Migration Scenario:

It appears there might be an intention to switch the active `sketchybar` configuration from `~/Code/sketchybar` to `~/Code/barista`.

**If this is the desired outcome, the steps would be:**

1.  **Remove the existing symlink**:
    ```bash
    rm ~/.config/sketchybar
    ```
2.  **Create a new symlink pointing to `barista`**:
    ```bash
    ln -s ~/Code/barista ~/.config/sketchybar
    ```
3.  **Restart `sketchybar` to apply the new configuration**:
    ```bash
    launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist
    launchctl load ~/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist
    ```

This document serves as a record of the current state and a proposed path forward, as the user was unsure about proceeding with the migration at this time.

## Progress Log — 2025-11-18

1. **Sync Audit**
   - Captured repo status for both `~/Code/barista` and `~/Code/sketchybar` (`docs/SYNC_AUDIT.md`).
   - Confirmed `~/.config/sketchybar -> ~/Code/sketchybar` symlink remains in place.
2. **Control Panel + Helper Parity**
   - `gui/` and `helpers/` directories mirrored into `~/Code/sketchybar` with `make all && make install`.
   - Documented in `docs/CONTROL_PANEL_PARITY.md`.
3. **Unified Control Center**
   - `menu_module.render_control_center` replaces separate Apple/front-app popups.
   - Single `control_center` item on the left opens consolidated menus for app controls, Yabai, spaces, dev tools, and help.
4. **Widget + System Panel Alignment**
   - Removed standalone `network` widget; Wi-Fi/IPv4 now surface inside the CPU/System panel (C helper + shell fallback updated).
   - Yabai status widget, spaces management scripts, and right-aligned widgets (battery, volume, clock/calendar) share consistent sizing via `widgets.lua`.
5. **Next Cutover Step**
   - Once QA on `~/Code/sketchybar` passes, re-point the `~/.config/sketchybar` symlink to `~/Code/barista` and reload the launch agent per steps above.

6. **Barista Control Center Expansion (In Progress)**
   - Direction: graduate from a “SketchyBar control panel” to a Barista-branded macOS control surface with:
     - Full launch-agent inventory + management (kickstart/bootstrap helpers, future automation).
     - Debug/diagnostic toggles (verbose logging, hotload, rebuild/reload macros).
     - Global shortcuts + CLI wrappers for rebuilding, reloading, or opening GUI popups.
     - Hooks for AI-assisted workflows (doc links, future Ollama/OpenAI triggers).
   - Documentation work:
     - `docs/IMPROVEMENTS.md` now tracks Launch-Agent, Debug, and Shortcut enhancements.
     - `docs/BARISTA_CONTROL_PANEL.md` (new) captures the expanded mission, UX pillars, and roadmap.
   - Upcoming milestones:
     - Ship `helpers/launch_agent_manager.sh` for list/start/stop/restart with JSON output.
     - Add Launch Agent + Debug tabs inside `gui/config_menu_enhanced.m`.
     - Introduce a first-class Barista launch agent that supervises sketchybar, yabai, and skhd.
