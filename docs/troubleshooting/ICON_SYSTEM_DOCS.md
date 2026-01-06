# Icon System Documentation

## Overview

The SketchyBar configuration uses Nerd Fonts for icon rendering. Icons are managed through a state-based system that allows dynamic updates via the GUI control panel.

## Icon Flow

```
state.json (icons) → main.lua (state_module.get_icon) → sketchybar item
       ↑
   GUI Control Panel (config_menu)
```

## How Icons Work

### 1. State Storage
Icons are stored in `~/.config/sketchybar/state.json`:

```json
{
  "icons": {
    "apple": "",
    "quest": "",
    "triforce": "󰊠",
    "calendar": "",
    "clock": "",
    "settings": ""
  }
}
```

### 2. Icon Loading in main.lua

```lua
-- Apple menu uses state icon system
sbar.add("item", "apple_menu", {
  position = "left",
  icon = state_module.get_icon(state, "apple", ""),  -- Loads from state.json
  label = { drawing = false },
  ...
})
```

### 3. GUI Control (config_menu)

The GUI at `~/.config/sketchybar/gui/bin/config_menu` allows you to:
- Select icons from dropdown menus
- Preview icons before applying
- Save changes to state.json
- Changes apply on next reload

## Available Icons

### System Icons (FontAwesome)
- Apple: `` (F179)
- Settings/Gear: `` (F013)
- Calendar: `` (F073)
- Clock: `` (F017)
- Power: `` (F011)

### Window Management (FontAwesome)
- Close/Times: `` (F00D)
- Eye (show): `` (F06E)
- Eye slash (hide): `` (F070)
- Expand: `` (F065)
- Arrows: `` (F0B2)

### Layout Icons (Material Design via Nerd Font)
- Triforce: `󰊠` (F02A0)
- BSP/Tile: `󰆾` (F01BE)
- Stack: `󰓩` (F04E9)
- Float: `󰒄` (F0484)

## Font Requirements

**Primary Font**: Hack Nerd Font (installed at `~/Library/Fonts/HackNerdFont-*.ttf`)

The font must include:
- FontAwesome glyphs (F000-F2E0)
- Material Design Icons (F0001-F1AF0+)
- Devicons (E700-E7C5)
- Custom Nerd Font glyphs

## Changing Icons

### Via GUI (Recommended)
1. Open control panel: `~/.config/sketchybar/gui/bin/config_menu`
2. Go to "Menu Icons" section
3. Select new icon from dropdown
4. Preview updates automatically
5. Click "Apply" or "Save"
6. Reload bar: `sketchybar --reload`

### Via state.json (Manual)
1. Edit `~/.config/sketchybar/state.json`
2. Update icon value in the `icons` object
3. Save file
4. Reload: `sketchybar --reload`

### Via Command Line (Temporary)
```bash
# Set icon directly (not persisted)
sketchybar --set apple_menu icon=""

# Verify
sketchybar --query apple_menu | grep '"value"'
```

## Icon Testing

Test if an icon renders correctly:

```bash
# In terminal
echo ""

# Or test with lua
lua -e 'print("")'
```

## Troubleshooting

### Icon Not Showing
1. **Check state.json**: Verify icon value is set
   ```bash
   cat ~/.config/sketchybar/state.json | jq '.icons.apple'
   ```

2. **Check main.lua**: Ensure it uses state_module.get_icon()
   ```lua
   icon = state_module.get_icon(state, "apple", "")
   ```

3. **Test direct set**: Bypass state system
   ```bash
   sketchybar --set apple_menu icon=""
   ```

4. **Verify font**: Check Hack Nerd Font is installed
   ```bash
   fc-list | grep -i "hack nerd"
   ```

### Icon Shows as Box/Question Mark
- Font doesn't have that glyph
- Try alternative icon from same font family
- Check codepoint exists in font

### Icons Work in Terminal But Not SketchyBar
- Check font path in sketchybar config
- Verify icon font is set correctly in main.lua
- Check if icon value has extra whitespace

## Icon Reference

### Finding New Icons

1. **Nerd Fonts Cheat Sheet**: https://www.nerdfonts.com/cheat-sheet
   - Search by name
   - Copy glyph directly
   - Note the codepoint

2. **FontAwesome**: https://fontawesome.com/icons
   - Free icons available
   - Codepoints start with F

3. **Material Design Icons**: https://materialdesignicons.com
   - Huge icon library
   - Codepoints in F0001-F1AF0+ range

### Icon Categories in config_menu.m

Located at `/Users/scawful/src/sketchybar/gui/config_menu.m:130-180`:

- System & Hardware (Apple, CPU, Network, Battery, etc.)
- Development (Terminal, Code, Git, VSCode, etc.)
- Files & Folders (Folder, File, Finder, etc.)
- Apps (Safari, Chrome, Calendar, Clock, etc.)
- Window Management (BSP, Stack, Float, Grid)
- Gaming & Entertainment (Gamepad, Quest, Triforce, etc.)

## Files Involved

```
~/.config/sketchybar/
├── state.json                    # Icon storage
├── main.lua                      # Icon loading
├── modules/
│   ├── state.lua                 # State management
│   ├── icons.lua                 # Icon library (fallback)
│   └── menu.lua                  # Menu icon definitions
└── gui/
    ├── bin/config_menu           # GUI for icon selection
    └── config_menu.m             # GUI source code
```

## Code Examples

### Adding a New Configurable Icon

1. **Add to state.json default**:
```json
{
  "icons": {
    "my_icon": ""
  }
}
```

2. **Use in main.lua**:
```lua
sbar.add("item", "my_widget", {
  icon = state_module.get_icon(state, "my_icon", ""),
  ...
})
```

3. **Add to GUI** (config_menu.m):
```objc
// Add to iconChoices array
@{ @"title": @"My Icon", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F123" }
```

### Menu Icons

Menu icons are defined directly in `modules/menu.lua`:

```lua
{
  type = "item",
  name = "menu.item.name",
  icon = "",  -- Direct icon glyph
  label = "Menu Item",
  action = "command to run"
}
```

## Best Practices

1. **Always use state for configurable icons** - Allows GUI control
2. **Use direct glyphs for static menu icons** - Simpler, no state needed
3. **Test icons before adding** - Verify they render correctly
4. **Document codepoints** - Include F### codes in comments
5. **Provide fallbacks** - Default icon if state icon missing
6. **Keep icon library updated** - Add new icons to config_menu.m

## Quick Reference Commands

```bash
# Reload bar
sketchybar --reload

# Set icon directly
sketchybar --set ITEM_NAME icon=""

# Query item
sketchybar --query ITEM_NAME

# Check state
cat ~/.config/sketchybar/state.json | jq '.icons'

# Open GUI
~/.config/sketchybar/gui/bin/config_menu

# Test icon renders
echo ""
```

---

**Last Updated**: 2025-01-17
**Maintainer**: SketchyBar Configuration
**Font**: Hack Nerd Font Bold 16pt
