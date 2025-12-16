# Components (Experimental)

This directory contains an experimental modular component architecture from the `fusion/restore-ui` branch (November 2025).

## Status: Experimental / Reference

These components are **not currently integrated** into the main barista configuration. They represent an alternative approach to widget creation that prioritizes:

- **Declarative Configuration**: Menu items defined as data structures
- **Clean Separation**: Each widget is self-contained
- **Context Injection**: Configuration passed via context objects

## Files

### apple_menu.lua
A declarative menu rendering system supporting:
- Headers, separators, and regular items
- Nested submenus with hover navigation
- Shortcut key display
- Click actions and environment variables

**Key Pattern:**
```lua
local items = {
  { type = "header", name = "menu.header", label = "System" },
  { type = "item", name = "menu.sleep", icon = "", label = "Sleep", action = "pmset displaysleepnow" },
  { type = "submenu", name = "menu.tools", icon = "", label = "Tools", items = {...} },
}
```

### yabai.lua
Yabai status widget with popup controls for:
- Space layout modes (float/bsp/stack)
- Window management (balance, rotate, flip)
- Space navigation

### clock.lua
Clock widget with calendar popup displaying:
- Current date/time
- Calendar grid
- Week summary

### front_app.lua
Front application display with app-specific popup menus.

## Future Integration

To use these components, they would need to be:
1. Imported into `main.lua`
2. Configured with the appropriate context (sbar, theme, settings, etc.)
3. Tested for compatibility with current state management

## Origin

Extracted from `~/Code/sketchybar` (branch `fusion/restore-ui`) during December 2025 cleanup.
See `docs/architecture/ARCHITECTURE_ANALYSIS.md` for detailed system documentation from the same branch.
