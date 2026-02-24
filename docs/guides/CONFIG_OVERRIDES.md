# Programmatic Configuration Overrides

Barista supports a programmatic override system that allows you to customize the bar's state without modifying the managed `state.json` or core Lua files.

## The `barista_config.lua` File

If a file named `barista_config.lua` exists in your SketchyBar configuration directory (`~/.config/sketchybar/`), it will be loaded automatically after the profile and `state.json` have been processed.

This file should return a Lua table containing the settings you wish to override.

### Example Configuration

```lua
-- ~/.config/sketchybar/barista_config.lua
local theme = require("theme")

return {
  -- Override bar appearance
  appearance = {
    bar_height = 30,
    corner_radius = 6,
    font_text = "JetBrainsMono Nerd Font",
  },

  -- Toggle specific widgets on/off
  widgets = {
    network = false,
    system_info = true,
  },

  -- Customize individual icons
  icons = {
    apple = "",
  }
}
```

## How it Works

1. **Loading**: Barista uses `loadfile` to read this script, ensuring that any changes you make are applied immediately whenever SketchyBar is reloaded.
2. **Deep Merge**: The returned table is recursively merged into the internal `state` object. This means you only need to specify the keys you want to change; everything else will remain at its default or profile-defined value.
3. **Precedence**: Overrides in this file take the highest precedence, surpassing both the defaults and the selected profile settings.

## Why use this instead of `state.json`?

- **Persistence**: `state.json` can be overwritten by the GUI or TUI configuration tools.
- **Logic**: Since it's a Lua file, you can add conditional logic (e.g., different settings based on the hostname or connected displays).
- **Safety**: It keeps your personal preferences separate from the project's core configuration files.
