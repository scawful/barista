# Sketchybar Configuration

This document explains the structure and features of this `sketchybar` configuration.

## Overview

This is a custom `sketchybar` configuration written in Lua. It provides a modern and interactive status bar with the following features:

-   **Dynamic Battery Indicator:** The battery icon changes color to reflect its status (Green for high, Yellow for medium, Red for low, and Blue when charging).
-   **Expanded Popup Menu:** A "Zelda" themed popup menu with useful shortcuts to applications and system functions.
-   **Themeable Color Scheme:** The color scheme is managed by a theme module, making it easy to customize the look of the bar.
-   **Version Control:** The configuration is tracked in a git repository, which makes it safer to introduce new changes.

## Configuration Files

The configuration is split into several files to keep it organized and easy to maintain:

-   `main.lua`: The main configuration file. It defines the bar, items, and their properties.
-   `theme.lua`: The theme module. It loads the current theme and returns the theme table.
-   `themes/`: A directory containing theme files. Each file returns a Lua table with color definitions.
    -   `default.lua`: The default theme with a full color palette.
    -   `halext.lua`: An alternative theme.
-   `plugins/`: A directory containing shell scripts that provide information to the bar items (e.g., battery status, clock).

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
    -   **Calendar:** Add a popup menu to the clock item to display a calendar.
    -   **Weather:** Add a popup menu to display the weather forecast.
-   **Refactor `sbar.exec` calls:** The `sbar.exec` calls for subscribing to events can be refactored to use the `item:subscribe()` method of the Lua wrapper, if the wrapper supports it. This would make the configuration even cleaner and more consistent. This was attempted before and broke the bar, so it should be approached with caution.

