# Barista Architecture & Troubleshooting Guide

## System Overview
Barista is a highly customized, modular status bar built on top of **SketchyBar**, integrating deeply with **yabai** (window manager) and **skhd** (hotkey daemon). It employs a hybrid architecture using Lua for configuration and compiled C binaries for high-performance rendering.

### Core Components
1.  **SketchyBar (`sketchybarrc` -> `main.lua`)**: The visual bar. It acts as the event loop and renderer. All configuration is driven by Lua scripts.
2.  **Yabai**: Manages windows and spaces. Barista queries yabai for space status and window layouts.
3.  **skhd**: Handles keyboard shortcuts. Barista generates a config file for skhd to trigger yabai commands.
4.  **Helper Binaries (`bin/`)**: Compiled C programs (e.g., `state_manager`, `menu_renderer`) used to offload heavy processing from shell scripts.

## Key Insights & Lessons Learned

### 1. Widget Ordering & Layout
*   **Addition Order Matters**: SketchyBar places `left` items in the order they are added. If you add Item A then Item B, the visual order is `[A] [B]`.
*   **Async Race Conditions**: Scripts like `spaces_setup.sh` run asynchronously. If they rely on anchoring to other items (e.g., "place spaces after Front App"), those anchor items *must* exist before the script runs.
*   **Fix**: Use `sleep` or polling loops in startup scripts to wait for anchors. In `main.lua`, ensure static items are created *before* triggering async scripts that depend on them.

### 2. Yabai Integration & Spaces
*   **Missing Spaces**: Often caused by `yabai` being unresponsive during startup. If `yabai -m query --spaces` returns empty, the space creation loop fails.
*   **Robustness**: `spaces_setup.sh` was rewritten to be resilient:
    *   It polls for the anchor item (`front_app`) before starting.
    *   It uses fallback anchors (`yabai_status` -> `front_app` -> `control_center`).
    *   It avoids complex array batching in Bash, favoring direct `sketchybar` calls for stability.
    *   It initializes variables (`last_item=""`) to prevent `set -u` crashes.

### 3. Shell Scripting Pitfalls
*   **`set -e` vs. Debugging**: While `set -e` is good for safety, it can silently kill scripts if a non-critical command (like a debug `echo`) fails.
*   **Variable Expansion**: Always quote variables (`"$item"`) to prevent word splitting, especially with JSON data.
*   **Eval & Arrays**: Avoid `eval` with complex strings. Constructing arguments in a loop and passing them directly (`sketchybar "${args[@]}"`) is safer, but sequential execution (one command at a time) is the most robust for debugging.

### 4. Process Management
*   **Zombie Processes**: `sketchybar --reload` usually works, but sometimes "ghost" items persist if the config file logic changes drastically (e.g., removing an item creation block). A full `brew services restart sketchybar` is the nuclear option to clear state.
*   **Permissions**: `sketchybar` requires **Accessibility** permissions to query the "Front App". If the label reads "Cursor" or doesn't update, toggle the permission in macOS System Settings.
*   **Yabai Scripting Addition**: Requires `sudo yabai --load-sa`. This must be allowed in `sudoers` (nopasswd) for seamless startup.

### 5. Lua Configuration (`main.lua`)
*   **Static Definition**: It is cleaner to define all static widgets in `main.lua` rather than creating them dynamically in shell scripts.
*   **Folding Functionality**: We successfully consolidated the `yabai_status` widget into the `front_app` popup menu. This involved moving the menu item definitions and removing the standalone widget creation code.

## Troubleshooting Checklist
1.  **Spaces not showing?**
    *   Check if `yabai` is running: `pgrep -x yabai`.
    *   Check `spaces_setup.sh` logs in `/tmp/spaces.log` (if enabled).
    *   Verify the anchor item exists (`sketchybar --query front_app`).
2.  **Front App label stuck?**
    *   Re-grant Accessibility permissions to SketchyBar.
    *   Ensure `plugins/front_app.sh` is executable (`chmod +x`).
3.  **Shortcuts not working?**
    *   Check if `skhd` is running.
    *   Verify `~/.config/skhd/skhdrc` or the sourced barista config matches your expectation.
4.  **Layout weird?**
    *   Check the order of `sbar.add` calls in `main.lua`.
    *   Check for `sketchybar --move` commands in setup scripts.

## File Locations
*   **Config**: `~/.config/sketchybar/` (Symlinked or copied from `~/Code/barista`).
*   **Main Entry**: `~/.config/sketchybar/main.lua`.
*   **Spaces Logic**: `~/.config/sketchybar/plugins/simple_spaces.sh` (Active) / `spaces_setup.sh` (Legacy/Complex).
*   **Yabai Control**: `~/.config/scripts/yabai_control.sh`.