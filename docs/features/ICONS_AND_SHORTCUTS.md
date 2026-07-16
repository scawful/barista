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

Barista includes a comprehensive keyboard shortcut management system with **non-conflicting** shortcuts using `cmd+alt`, plus a small `ctrl`/`ctrl+shift` layer.

### Design Philosophy

- **Non-Conflicting**: Uses `cmd+alt` (⌘⌥) combinations that avoid app conflicts
- **Lightweight**: Keeps `ctrl` for space navigation and `ctrl+shift` for layout modes
- **Consistent**: All shortcuts follow logical patterns
- **Documented**: Every shortcut has a description and symbol

### Global Shortcuts (cmd+alt)

These shortcuts work system-wide and don't conflict with common applications:

#### Barista UI
- `⌘⌥P` - Open Barista
- `⌘⌥D` - Open the clock Task Focus popup, then refresh it asynchronously
- `⌘⌥N` - Capture a task (generated only when a task source is configured)
- `⌘⌥/` - Toggle Control Center
- `⌘⌥H` - Open Help Center
- `⌘⌥I` - Open Icon Browser
- `⌘⌥T` - Open Terminal
- `⌘⌥O` - Toggle Keyboard Overlay
- `⌘⌥R` - Reload SketchyBar
- `⌘⌥⇧R` - Rebuild + Reload SketchyBar
- `⌘⌥Y` - Toggle Yabai Shortcuts

#### Apps
- `⌘⌥Z` - Launch z3ed in Ghostty

Note: The `z3ed` shortcut only appears when a `z3ed` launcher is found. It launches through Ghostty when Ghostty is installed and falls back to Terminal-backed shell execution otherwise.

Task Focus and Task Pulse read the same machine-local
`menus.calendar.task_sources` configuration. The committed default is empty;
Barista does not impose a personal board on fresh or Work installs. Set
`menus.calendar.task_provider` to `files` for local Markdown/Org parsing or
`syshelp` for `syshelp plan tasks json` plus CLI capture.
For launchd environments with a reduced `PATH`, set the ignored local
`menus.calendar.syshelp_path` to the absolute executable instead of committing
a machine-specific path.

`⌘⌥D` remains available as the calendar/task-status entry point. `⌘⌥N` is
conditional: it is included in the generated skhd map only when a task source
exists in state or `BARISTA_CALENDAR_TASK_SOURCES` / `BARISTA_TASK_SOURCES`.
With the `files` provider, capture opens the configured board without mutating
it. With the explicit `syshelp` provider, capture uses
`syshelp plan tasks add` and triggers `task_state_changed` after success.

#### AFS app paths
- The AFS Browser shortcut prefers `AFS_BROWSER_APP`, then falls back to the local `afs-studio` launcher/binary.
- AFS Studio prefers the manifest-backed `%CODE%/tools/afs/launch.sh` launcher,
  then an installed binary or the legacy `afs-scawful` launcher. AFS Labeler is
  hidden unless an explicit or installed Labeler binary exists.

#### Display Management
- `⌘⌥⇧→` - Send Window to Next Display
- `⌘⌥⇧←` - Send Window to Prev Display

#### Space Navigation (ctrl)
- `⌃←` - Previous Space
- `⌃→` - Next Space

Note: Space navigation wraps within the current display and relies on the yabai scripting addition for instant switching. If it stops working, reload the scripting addition or run the Yabai doctor.

#### Layout Modes (ctrl+shift)
- `⌃⇧F` - Set Float Layout
- `⌃⇧B` - Set BSP Layout
- `⌃⇧S` - Set Stack Layout

Note: Window-manager shortcuts are generated only when `modes.window_manager` permits them. Use `BARISTA_WINDOW_MANAGER_MODE=disabled` (or set `state.json` to disabled/optional) to suppress yabai/skhd bindings on machines without permissions.

### Generating skhd Configuration

Generate the skhd configuration and Help Center workflow reference:

```bash
# From the Barista repo
BARISTA_CONFIG_DIR=/path/to/barista lua helpers/generate_shortcuts.lua

# From an installed config
lua ~/.config/sketchybar/helpers/generate_shortcuts.lua

# Output: ~/.config/skhd/barista_shortcuts.conf
# Also updates: data/workflow_shortcuts.json
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
Open Task Focus     ⌘⌥D
Capture Task        ⌘⌥N  (when configured)
Reload SketchyBar   ⌘⌥R
Open Barista        ⌘⌥P
```

Help Center + Barista shortcut data is generated into
`data/workflow_shortcuts.json` from `modules/shortcuts.lua`. For machine-local
editor/shell entries, docs, and quick actions, copy
`data/workflow_shortcuts.local.example.json` to the ignored
`data/workflow_shortcuts.local.json` and generate an ignored local view with:

```bash
BARISTA_WORKFLOW_EXTRAS=data/workflow_shortcuts.local.json \
  lua helpers/generate_shortcuts.lua
```

Do not hand-edit either generated file.

## Best Practices

### Icons

1. **Use icon_manager**: Always prefer `icon_manager.get_char()` over hardcoded glyphs
2. **Provide fallbacks**: Use the fallback parameter when needed
3. **Test across fonts**: Verify icons display correctly with different font setups
4. **Register custom icons**: Add your custom icons to icon_manager for consistency

### Shortcuts

1. **Avoid conflicts**: Stick to cmd+alt and ctrl/ctrl+shift combinations for global shortcuts
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

- [ ] GUI shortcut editor in Barista
- [ ] Per-application shortcut contexts
- [ ] Shortcut recording/learning mode
- [x] Icon browser in Barista
- [ ] Custom icon upload/import
- [ ] Theme-specific icon sets
- [ ] Dynamic icon based on state (battery level, wifi strength)
