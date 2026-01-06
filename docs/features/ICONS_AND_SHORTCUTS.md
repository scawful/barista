# Icons and Shortcuts Management

## Icon Management System

Barista includes a centralized, font-agnostic icon management system that supports multiple icon fonts with automatic fallback.

### Features

- **Multi-Font Support**: Automatically loads icons from multiple font families
- **Fallback System**: If an icon isn't available in the preferred font, falls back to alternatives
- **Font-Agnostic**: Works with Hack Nerd Font, SF Symbols, SF Pro, and more
- **Centralized**: One place to manage all icons across the entire configuration

### Supported Fonts

Icons are loaded from these fonts in order of priority:

1. **Hack Nerd Font** (priority 1) - Primary icon font with comprehensive glyphs
2. **SF Pro** (priority 2) - Apple's San Francisco font
3. **SF Symbols** (priority 3) - Apple's symbol font
4. **Menlo** (priority 4) - Fallback monospace font

### Using Icons in Configuration

```lua
-- Get an icon character
local apple_icon = icon_manager.get_char("apple")

-- Get icon with font information
local icon_info = icon_manager.get("apple")
-- Returns: {char = "", font = "Hack Nerd Font", style = "Bold"}

-- Get font string for SketchyBar
local font_string = icon_manager.get_font_string("apple", 16)
-- Returns: "Hack Nerd Font:Bold:16.0"

-- Create full SketchyBar icon config
local icon_config = icon_manager.create_config("apple", 16, nil, "0xFFFFFFFF")
-- Returns: {value = "", font = "Hack Nerd Font:Bold:16.0", color = "0xFFFFFFFF"}
```

### Available Icons

The icon manager includes icons for:

- **System**: apple, settings, power, sleep, lock, calendar, clock, battery, volume, wifi
- **Window Management**: window, tile, stack, float, fullscreen
- **Development**: code, terminal, emacs, git
- **Gaming/ROM**: gamepad, rom

### Adding Custom Icons

Register your own icons with multi-font support:

```lua
icon_manager.register("my_icon", {
  {char = "", font = "Hack Nerd Font", desc = "My custom icon (Nerd Font)"},
  {char = "⚡", font = "SF Pro", desc = "My custom icon (SF Pro)"},
})
```

### Icon Inspection

Debug and inspect icon information:

```lua
-- Get info about an icon
local info = icon_manager.get_info("apple")
-- Returns: {name = "apple", glyphs = [{char = "", font = "Hack Nerd Font", desc = "..."}]}

-- List all available icons
local icons = icon_manager.list_icons()
-- Returns: {"apple", "battery", "calendar", ...}
```

## Keyboard Shortcuts System

Barista includes a comprehensive keyboard shortcut management system with **non-conflicting** shortcuts using `cmd+alt`, `fn`, and a small `ctrl+shift` layer.

### Design Philosophy

- **Non-Conflicting**: Uses `cmd+alt` (⌘⌥) and `fn` (🌐) combinations that avoid app conflicts
- **fn Key Support**: Leverages the fn (globe) key for window/space control (macOS Ventura+)
- **Consistent**: All shortcuts follow logical patterns
- **Documented**: Every shortcut has a description and symbol

### Global Shortcuts (cmd+alt)

These shortcuts work system-wide and don't conflict with common applications:

#### Barista UI
- `⌘⌥P` - Open Control Panel
- `⌘⌥C` - Toggle Cortex
- `⌘⌥/` - Toggle Control Center
- `⌘⌥K` - Toggle WhichKey HUD
- `⌘⌥H` - Open Help Center
- `⌘⌥I` - Open Icon Browser
- `⌘⌥R` - Reload SketchyBar
- `⌘⌥⇧R` - Rebuild + Reload SketchyBar
- `⌘⌥Y` - Toggle Yabai Shortcuts

#### Display Management
- `⌘⌥⇧→` - Send Window to Next Display
- `⌘⌥⇧←` - Send Window to Prev Display

#### Layout Modes (ctrl+shift)
- `⌃⇧F` - Set Float Layout
- `⌃⇧B` - Set BSP Layout
- `⌃⇧S` - Set Stack Layout

### fn Key Shortcuts

The shortcuts module includes fn-key combinations (requires skhd configuration):

#### Window Navigation (fn + vim keys)
- `fn-h` - Focus Window West
- `fn-j` - Focus Window South
- `fn-k` - Focus Window North
- `fn-l` - Focus Window East

#### Space Navigation (fn + numbers)
- `fn-1` to `fn-0` - Focus Spaces 1-10

#### Space Navigation (fn + arrows)
- `fn-←` - Previous Space
- `fn-→` - Next Space

#### Space Movement (fn + shift + arrows)
- `fn-⇧←` - Send Window to Prev Space
- `fn-⇧→` - Send Window to Next Space

#### Quick Actions (fn + key)
- `fn-t` - Toggle Layout
- `fn-f` - Toggle Fullscreen
- `fn-r` - Rotate Layout
- `fn-b` - Balance Windows
- `fn-space` - Toggle Float

#### Window Sizing (fn + arrows)
- `fn-↑` - Maximize Window
- `fn-↓` - Restore Window

### Generating skhd Configuration

Generate the shortcuts configuration file:

```bash
# Generate shortcuts config (uses BARISTA_CONFIG_DIR if set)
lua ~/.config/sketchybar/helpers/generate_shortcuts.lua

# Output: ~/.config/skhd/barista_shortcuts.conf
```

### Integrating with skhd

Add to your `~/.config/skhd/skhdrc`:

```bash
# Load barista shortcuts
.load "/Users/<user>/.config/skhd/barista_shortcuts.conf"
```

Note: skhd requires the `.load` line to use double quotes and an absolute path. If shortcuts stop working, run:

```bash
~/.config/sketchybar/scripts/yabai_control.sh doctor --fix
```

Then restart skhd:

```bash
# Restart skhd service
brew services restart skhd

# Or just reload config
skhd --reload
```

### Customizing Shortcuts

Edit `modules/shortcuts.lua` to customize:

```lua
-- Add a new shortcut
table.insert(shortcuts.global, {
  mods = {"cmd", "alt"},
  key = "m",
  action = "my_custom_action",
  desc = "My Custom Action",
  symbol = "⌘⌥M"
})

-- Define the action
shortcuts.actions.my_custom_action = "osascript -e 'display notification \"Hello!\"'"
```

### Checking for Conflicts

The shortcuts module can check for conflicts:

```lua
local shortcuts = require("shortcuts")
local conflicts = shortcuts.check_conflicts()

if #conflicts > 0 then
  for _, conflict in ipairs(conflicts) do
    print("Conflict:", conflict.combo)
  end
end
```

### Listing All Shortcuts

Get a list of all shortcuts programmatically:

```lua
local shortcuts = require("shortcuts")
local list = shortcuts.list_all()

for _, shortcut in ipairs(list) do
  print(shortcut.symbol, "-", shortcut.desc)
  print("  Command:", shortcut.command)
end
```

## Menu Shortcuts

Icons and shortcuts are automatically integrated into menu items. Shortcuts are displayed next to menu items:

```
Toggle Float        🌐␣
Toggle Fullscreen   🌐F
Open Control Panel  ⌘⌥P
```

## Best Practices

### Icons

1. **Use icon_manager**: Always prefer `icon_manager.get_char()` over hardcoded glyphs
2. **Provide fallbacks**: Use the fallback parameter when needed
3. **Test across fonts**: Verify icons display correctly with different font setups
4. **Register custom icons**: Add your custom icons to icon_manager for consistency

### Shortcuts

1. **Avoid conflicts**: Stick to cmd+alt and fn combinations for global shortcuts
2. **Document everything**: Add descriptions and symbols to all shortcuts
3. **Use logical groups**: Group related shortcuts (e.g., all display shortcuts use arrows)
4. **Test thoroughly**: Ensure shortcuts don't conflict with your most-used apps

## Troubleshooting

### Icons Not Displaying

1. **Check font installation**:
   ```bash
   # Install Hack Nerd Font
   brew tap homebrew/cask-fonts
   brew install --cask font-hack-nerd-font
   ```

2. **Verify icon exists**:
   ```lua
   lua -e "
   package.path = package.path .. ';~/.config/sketchybar/modules/?.lua'
   local im = require('icon_manager')
   print(im.get_char('apple'))
   "
   ```

3. **Check SketchyBar logs**:
   ```bash
   log show --predicate 'process == "sketchybar"' --last 5m
   ```

### Shortcuts Not Working

1. **Verify skhd is running**:
   ```bash
   brew services list | grep skhd
   ```

2. **Check skhd configuration**:
   ```bash
   cat ~/.config/skhd/barista_shortcuts.conf
   ```

3. **Reload skhd**:
   ```bash
   skhd --reload
   ```

4. **Check for conflicts**:
   ```bash
   lua ~/.config/sketchybar/helpers/generate_shortcuts.lua
   ```

## Future Enhancements

Planned improvements:

- [ ] GUI shortcut editor in Control Panel
- [ ] Per-application shortcut contexts
- [ ] Shortcut recording/learning mode
- [ ] Icon browser in Control Panel
- [ ] Custom icon upload/import
- [ ] Theme-specific icon sets
- [ ] Dynamic icon based on state (battery level, wifi strength)
