# Sketchybar Configuration

This document explains the structure and features of this `sketchybar` configuration.

## Overview

This is a custom `sketchybar` configuration written in Lua. It provides a modern and interactive status bar with the following features:

-   **Dynamic Widgets:** Battery/network/system-info/clock panels all expose hover popups (calendar, docs, quick actions) with Catppuccin styling and live font scaling.
-   **macOS-style Apple Menu:** The Apple icon opens a hover-driven menu with nested submenus (SketchyBar styles/tools, Yabai controls, window actions, app shortcuts, help). Shift-clicking the Apple icon recompiles/launches the Cocoa control panel.
-   **Per-space Yabai Control:** Spaces float by default, with BSP/stack toggles, per-window move/send actions, and an “Focus Emacs Space” shortcut.
-   **Themeable Glass Presets:** Built-in Liquid/Tinted/Classic/Solid presets update the bar color + blur, and the control panel stores more granular tweaks inside `state.json`.
-   **Version Control:** The configuration is tracked in git, making experimentation safe and reversible.

## Configuration Files

The configuration is split into several files to keep it organized and easy to maintain:

-   `main.lua`: The main configuration file. It defines the bar, items, and their properties.
-   `theme.lua`: The theme module. It loads the current theme and returns the theme table.
-   `themes/`: A directory containing theme files. Each file returns a Lua table with color definitions.
    -   `default.lua`: The default theme with a full color palette.
    -   `halext.lua`: An alternative theme.
-   `plugins/`: A directory containing shell scripts that provide information to the bar items (e.g., battery status, clock).
-   `gui/`: Source for the Objective-C control panel (`config_menu`). Run `make` in this folder whenever you modify `config_menu.m`.

## Theming

The color scheme of the bar is managed by a theme module.

-   **To change the theme:** Modify the `current_theme` variable in `theme.lua` to the name of the theme file you want to use (without the `.lua` extension).
-   **To create a new theme:** Create a new Lua file in the `themes/` directory. This file should return a Lua table with the color definitions you want to use. You can use `themes/default.lua` as a template.

## Future Improvements

Here are some ideas for making the bar more modern and interactive. A future agent can use these ideas to further enhance the configuration:

-   **Dynamic Theme Switching:** Implement a way to switch themes without manually editing the configuration file. This could be done through a popup menu item that lists the available themes.
-   **More Interactive Items:**
    -   **CPU/Memory Usage:** Add items to display system resource usage with graphs or charts. The `helpers/event_providers` directory already contains some code for this that could be integrated.
    -   **Network Indicator:** Add an item to display network information, such as the Wi-Fi SSID, IP address, and network speed.
    -   **Music/Playerctl:** Add an item to display the currently playing song and provide controls (play/pause, next, previous) for the music player.
-   **More Advanced Menus:**
    -   **Weather:** Add a popup menu to display the weather forecast.
-   **Refactor `sbar.exec` calls:** The `sbar.exec` calls for subscribing to events can be refactored to use the `item:subscribe()` method of the Lua wrapper, if the wrapper supports it. This would make the configuration even cleaner and more consistent. This was attempted before and broke the bar, so it should be approached with caution.

## Control Panel, Help, & State

- Click the Apple icon to open the system menu; **Shift+Click** rebuilds (if missing) and launches the Cocoa control panel (`gui/bin/config_menu`). Build logs land in `/tmp/sketchybar_gui_build.log` if something fails.
- The control panel is still the one-stop UI for widget toggles, appearance (height/corner/color/blur/scale), glyph previews, per-space icons, and shortcut remapping.
- A “Help & Tips” submenu inside the Apple menu links directly to `README.md`, `HANDOFF.md`, and a quick cheatsheet dialog so future operators can find onboarding info without digging through git history.
- Persistent state lives in `~/.config/sketchybar/state.json`. It is re-sanitized every time `main.lua` loads it, so corrupted JSON should heal automatically.
- **Sharing / onboarding**: see `docs/SHARING.md` for a turnkey flow to clone this repo on another Mac, apply the “shared” profile (Yaze/Emacs disabled by default), and customize docs/actions via the workflow JSON + Help Center.
- The Apple menu’s new **Dev Utilities** submenu (alongside the WhichKey HUD) is driven by `data/menu_help.json`, so adding documentation links or automation knobs is as easy as editing JSON instead of Lua.
- `plugins/clock.sh` and `plugins/system_info.sh` automatically defer to the compiled helpers in `~/.config/sketchybar/bin/clock_widget` and `~/.config/sketchybar/bin/system_info_widget` (build via `cd helpers && make install`) for lower CPU impact. The same install step also drops optimized binaries for submenu hover/anchor handling **and** the new `menu_action` dispatcher, keeping the Apple menu responsive even when you skim across popups or run long-running menu actions.

## Icon Map & Glyph Library

- Custom per-app glyphs are written to `~/.config/sketchybar/icon_map.json`. Use the control panel or run `~/.config/scripts/set_app_icon.sh "App Name" "glyph"` to add/edit entries.
- `~/.config/scripts/app_icon.sh` merges the JSON map with a curated fallback table so both the front-app item and the per-space icons stay in sync.
- The control panel exposes a “Library Presets” dropdown plus an “Open icon_map.json” button for fast iteration.

## Spaces & Shortcuts

- `plugins/spaces_setup.sh` rebuilds the spaces strip every time Yabai emits a `space_changed` or `display_changed` event. If Yabai is offline, it falls back to ten numbered placeholders so the UI never goes blank.
- `plugins/refresh_spaces.sh` is the entry point we hand to Yabai signals. It runs `spaces_setup.sh` and then calls `~/.config/scripts/update_external_bar.sh` so the bar height reservation stays in sync with the current configuration.
- `plugins/space.sh` now keeps numeric labels visible, highlights hovers in the Catppuccin palette, and swaps icons to the primary app in that space whenever Yabai can be queried.
- Toggle the custom Yabai shortcuts off from the control panel (the segmented control under “Space Switching”) or by running `~/.config/scripts/toggle_yabai_shortcuts.sh off` to keep macOS' default `ctrl` + arrow behavior.
- `~/.config/scripts/update_external_bar.sh` reapplies `yabai -m config external_bar` using the configured bar height whenever the bar reloads or displays change, so maximized windows respect the drop bar on every monitor.

## Diagnostics & Recovery

- Tail logs with `~/.config/scripts/bar_logs.sh sketchybar 100` (pass `--follow` to stream). The script also understands `yabai` and `skhd` targets.
- Repair Accessibility permissions via the control panel's “Repair Accessibility Services” button (which runs `~/.config/scripts/yabai_accessibility_fix.sh`). That script reopens System Settings, reloads all LaunchAgents, and reinstalls the Yabai scripting addition.
- Run `~/.config/scripts/yabai_doctor.sh` to verify the Yabai LaunchAgent/socket/scripting addition before restarting services; it summarizes the most common failure points.
- Reload the bar from the Zelda popup or the control panel after editing Lua/scripts so changes take effect immediately.
