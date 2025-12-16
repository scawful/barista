# Complete Icon Reference Guide

**Version:** 2.0
**Last Updated:** November 17, 2025
**Font:** Hack Nerd Font / FontAwesome / Material Design Icons

## Quick Reference

Use this guide to find icons for any UI element in your SketchyBar configuration.

## How to Use Icons

### In Lua Configuration (main.lua)
```lua
-- Direct icon assignment
icon = ""  -- Apple icon

-- Using icon_for helper (with fallback)
icon = icon_for("apple", "")

-- Using C bridge (fastest, with fallback chain)
icon = c_bridge.icons.get("apple", icon_for("apple", ""))
```

### In Control Panel
1. Open Control Panel: Shift + Click Apple menu
2. Go to Icons tab
3. Search or browse categories
4. Click icon to copy or assign

### In state.json
```json
{
  "icons": {
    "apple": "",
    "battery": "",
    "clock": ""
  }
}
```

---

## Complete Icon Library

### System Icons (32 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `apple` |  | F179 | Apple menu, macOS branding |
| `apple_alt` |  | F118 | Alternative Apple logo |
| `settings` |  | F013 | Settings, preferences |
| `gear` |  | F013 | Settings (alias) |
| `cog` |  | F013 | Configuration |
| `power` |  | F011 | Power, shutdown |
| `power_off` |  | F011 | Power off |
| `lock` | 󰷛 | F0DF | Lock screen, security |
| `unlock` | 󰿨 | F0FF | Unlock |
| `notification` | 󰂚 | F009A | Notifications |
| `bell` | 󰂚 | F009A | Alerts |
| `sleep` | 󰒲 | F04B2 | Sleep mode |
| `restart` |  | F01E | Restart system |
| `search` |  | F002 | Search, find |
| `magnify` |  | F00E | Zoom in |
| `help` |  | F059 | Help, info |
| `info` |  | F05A | Information |
| `warning` |  | F071 | Warning, caution |
| `error` |  | F057 | Error, critical |
| `check` |  | F00C | Success, complete |
| `close` |  | F00D | Close, cancel |
| `menu` | 󰍜 | F035C | Menu, hamburger |
| `more` |  | F141 | More options |
| `desktop` | 󰆍 | F018D | Desktop, display |
| `monitor` | 󰍹 | F0379 | External monitor |
| `laptop` |  | F109 | Laptop |
| `keyboard` | 󰌌 | F030C | Keyboard |
| `mouse` | 󰍽 | F037D | Mouse |
| `trash` |  | F1F8 | Delete, trash |
| `home` |  | F015 | Home directory |
| `user` |  | F007 | User account |
| `users` |  | F0C0 | Multiple users |

### Hardware & Monitoring (24 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `battery` |  | F240 | Battery widget |
| `battery_full` |  | F240 | 100% battery |
| `battery_three_quarters` |  | F241 | 75% battery |
| `battery_half` |  | F242 | 50% battery |
| `battery_quarter` |  | F243 | 25% battery |
| `battery_empty` |  | F244 | 0% battery |
| `battery_charging` |  | F1E6 | Charging indicator |
| `plug` |  | F1E6 | Power adapter |
| `wifi` | 󰖩 | F05A9 | WiFi connected |
| `wifi_off` | 󰖪 | F05AA | WiFi disconnected |
| `network` | 󰖩 | F05A9 | Network |
| `ethernet` | 󰈀 | F0200 | Wired connection |
| `bluetooth` | 󰂯 | F00AF | Bluetooth |
| `bluetooth_off` | 󰂲 | F00B2 | Bluetooth off |
| `volume` |  | F028 | Volume widget |
| `volume_up` |  | F028 | Volume high |
| `volume_down` |  | F027 | Volume low |
| `volume_mute` | 󰝟 | F075F | Muted |
| `brightness` | 󰃞 | F00DE | Brightness |
| `brightness_up` | 󰃠 | F00E0 | Increase brightness |
| `brightness_down` | 󰃟 | F00DF | Decrease brightness |
| `cpu` | 󰻠 | F0EE0 | CPU usage |
| `memory` | 󰘚 | F061A | RAM usage |
| `disk` | 󰋊 | F02CA | Disk space |
| `temperature` | 󰔄 | F0504 | Temperature |

### Time & Calendar (12 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `clock` |  | F017 | Clock widget |
| `time` |  | F017 | Time display |
| `timer` |  | F0E5 | Timer, countdown |
| `stopwatch` |  | F2F2 | Stopwatch |
| `alarm` | 󰀠 | F0020 | Alarm |
| `calendar` |  | F073 | Calendar widget |
| `calendar_today` | 󰃭 | F00ED | Today |
| `calendar_week` | 󰨳 | F0A33 | Week view |
| `calendar_month` | 󰃮 | F00EE | Month view |
| `date` |  | F133 | Date picker |
| `schedule` | 󰃰 | F00F0 | Schedule, agenda |
| `event` | 󰀠 | F0020 | Calendar event |

### Window Management (18 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `window` | 󰖲 | F05B2 | Window |
| `tile` | 󰆾 | F01BE | Tile mode |
| `bsp` | 󰆾 | F01BE | BSP layout |
| `stack` | 󰓩 | F04E9 | Stack layout |
| `float` | 󰒄 | F0484 | Float mode |
| `fullscreen` | 󰊓 | F0293 | Fullscreen |
| `minimize` |  | F2D1 | Minimize window |
| `maximize` | 󰀃 | F0003 | Maximize window |
| `close_window` |  | F00D | Close window |
| `split_h` | 󰤼 | F093C | Horizontal split |
| `split_v` | 󰤻 | F093B | Vertical split |
| `resize` | 󰁔 | F0054 | Resize |
| `move` | 󰁔 | F0054 | Move window |
| `sticky` | 󰐃 | F0403 | Sticky window |
| `focus` | 󰐃 | F0403 | Focus window |
| `swap` | 󰁔 | F0054 | Swap windows |
| `rotate` |  | F01E | Rotate layout |
| `mirror` | 󰥛 | F095B | Mirror layout |

### Development (32 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `terminal` |  | F120 | Terminal app |
| `console` |  | F120 | Console |
| `shell` |  | F489 | Shell script |
| `code` |  | F121 | Code editor |
| `vscode` | 󰨞 | F0A1E | VS Code |
| `vim` |  | F1C9 | Vim editor |
| `neovim` |  | F27A4 | Neovim |
| `emacs` |  | F1B8 | Emacs |
| `atom` |  | F2A2 | Atom editor |
| `sublime` |  | F114 | Sublime Text |
| `git` |  | F1D3 | Git |
| `github` |  | F09B | GitHub |
| `gitlab` |  | F296 | GitLab |
| `branch` |  | F126 | Git branch |
| `commit` |  | F044 | Git commit |
| `pull` |  | F019 | Git pull |
| `push` |  | F01B | Git push |
| `merge` |  | F015B | Git merge |
| `docker` |  | F395 | Docker |
| `kubernetes` | 󰠳 | F0833 | Kubernetes |
| `npm` |  | F1D1 | NPM |
| `nodejs` |  | F419 | Node.js |
| `python` |  | F3E2 | Python |
| `rust` |  | F25B | Rust |
| `go` | 󰟓 | F07D3 | Go language |
| `java` |  | F4E4 | Java |
| `javascript` |  | F430 | JavaScript |
| `typescript` | 󰛦 | F06E6 | TypeScript |
| `react` |  | F41B | React |
| `vue` | 󰡄 | F0844 | Vue.js |
| `angular` | 󰚣 | F06A3 | Angular |
| `database` |  | F1C0 | Database |

### Applications (48 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `finder` | 󰀶 | F0036 | macOS Finder |
| `safari` | 󰀹 | F0039 | Safari browser |
| `chrome` |  | F268 | Chrome browser |
| `firefox` |  | F269 | Firefox browser |
| `brave` | 󰊯 | F02AF | Brave browser |
| `edge` | 󰇩 | F01E9 | Edge browser |
| `messages` | 󰍦 | F0366 | Messages app |
| `mail` | 󰇮 | F01EE | Mail app |
| `outlook` | 󰴢 | F0D22 | Outlook |
| `gmail` | 󰊫 | F02AB | Gmail |
| `music` |  | F001 | Music app |
| `spotify` |  | F1BC | Spotify |
| `itunes` |  | F265 | iTunes |
| `apple_music` |  | F001 | Apple Music |
| `photos` |  | F03E | Photos app |
| `video` |  | F03D | Video player |
| `camera` |  | F030 | Camera app |
| `notes` |  | F249 | Notes app |
| `reminders` |  | F058 | Reminders |
| `calendar_app` |  | F073 | Calendar app |
| `contacts` |  | F2B9 | Contacts |
| `maps` |  | F279 | Maps app |
| `calculator` |  | F1EC | Calculator |
| `weather` | 󰖐 | F0590 | Weather |
| `cloud` |  | F0C2 | Cloud storage |
| `dropbox` |  | F16B | Dropbox |
| `gdrive` | 󰊶 | F02B6 | Google Drive |
| `icloud` | 󰀸 | F0038 | iCloud |
| `onedrive` | 󰅬 | F016C | OneDrive |
| `slack` | 󰒱 | F04B1 | Slack |
| `discord` | 󱚺 | F0676 | Discord |
| `teams` | 󰊻 | F02BB | Microsoft Teams |
| `zoom` |  | F2A7 | Zoom |
| `skype` |  | F17E | Skype |
| `notion` | 󰈙 | F0219 | Notion |
| `obsidian` |  | F0000 | Obsidian |
| `bear` | 󰛉 | F06C9 | Bear notes |
| `evernote` |  | F066 | Evernote |
| `xcode` |  | F154 | Xcode |
| `intellij` |  | F2B9 | IntelliJ |
| `pycharm` |  | F2B9 | PyCharm |
| `android_studio` |  | F2B9 | Android Studio |
| `photoshop` |  | F26E | Photoshop |
| `illustrator` |  | F27C | Illustrator |
| `figma` |  | F07B1 | Figma |
| `sketch` |  | F27E | Sketch |
| `blender` | 󰂫 | F00AB | Blender |
| `steam` |  | F1B6 | Steam |
| `playstation` | 󰊗 | F0297 | PlayStation |

### Files & Folders (16 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `folder` |  | F07B | Folder |
| `folder_open` |  | F07C | Open folder |
| `file` |  | F15B | Generic file |
| `file_text` |  | F15C | Text file |
| `file_code` |  | F1C9 | Code file |
| `file_image` |  | F1C5 | Image file |
| `file_video` |  | F1C8 | Video file |
| `file_audio` |  | F1C7 | Audio file |
| `file_archive` |  | F1C6 | Archive/ZIP |
| `file_pdf` |  | F1C1 | PDF document |
| `document` |  | F0F6 | Document |
| `save` |  | F0C7 | Save file |
| `download` |  | F019 | Download |
| `upload` |  | F01B | Upload |
| `cloud_download` |  | F0ED | Cloud download |
| `cloud_upload` |  | F0EE | Cloud upload |

### Gaming & Entertainment (12 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `gamepad` |  | F11B | Gaming |
| `controller` | 󰖺 | F05BA | Game controller |
| `dice` | 󰆹 | F01B9 | Dice, random |
| `puzzle` | 󰉌 | F024C | Puzzle, games |
| `triforce` | 󰊠 | F02A0 | Zelda triforce |
| `quest` | 󰊠 | F02A0 | Quest/adventure |
| `sword` | 󰚠 | F06A0 | Sword |
| `shield` | 󰞀 | F0780 | Shield |
| `trophy` |  | F091 | Achievement |
| `star` |  | F005 | Favorite, rating |
| `heart` |  | F004 | Like, favorite |
| `fire` |  | F06D | Hot, trending |

### Arrows & Navigation (20 icons)

| Name | Icon | Unicode | Usage |
|------|------|---------|-------|
| `arrow_up` |  | F062 | Up arrow |
| `arrow_down` |  | F063 | Down arrow |
| `arrow_left` |  | F060 | Left arrow |
| `arrow_right` |  | F061 | Right arrow |
| `chevron_up` |  | F077 | Chevron up |
| `chevron_down` |  | F078 | Chevron down |
| `chevron_left` |  | F053 | Chevron left |
| `chevron_right` |  | F054 | Chevron right |
| `caret_up` |  | F0D8 | Caret up |
| `caret_down` |  | F0D7 | Caret down |
| `caret_left` |  | F0D9 | Caret left |
| `caret_right` |  | F0DA | Caret right |
| `angle_up` |  | F106 | Angle up |
| `angle_down` |  | F107 | Angle down |
| `angle_left` |  | F104 | Angle left |
| `angle_right` |  | F105 | Angle right |
| `forward` |  | F04E | Forward |
| `backward` |  | F04A | Backward |
| `refresh` |  | F021 | Refresh, reload |
| `sync` |  | F021 | Synchronize |

---

## Icon Categories Summary

| Category | Count | Use Case |
|----------|-------|----------|
| System | 32 | OS controls, basic UI |
| Hardware | 24 | Battery, WiFi, volume, monitoring |
| Time & Calendar | 12 | Clock, calendar widgets |
| Window Management | 18 | Yabai/window operations |
| Development | 32 | Code editors, version control |
| Applications | 48 | App icons, common programs |
| Files & Folders | 16 | File operations |
| Gaming | 12 | Games, entertainment |
| Arrows & Navigation | 20 | UI navigation |
| **TOTAL** | **214 icons** | |

---

## Usage Examples

### Setting Icon in main.lua

```lua
-- Direct assignment
sbar.add("item", "my_widget", {
  icon = "",  -- Apple icon
  label = "Menu"
})

-- With icon_for helper (searches state + fallback)
sbar.add("item", "my_widget", {
  icon = icon_for("apple", ""),  -- Try state, fallback to
  label = "Menu"
})

-- With C bridge (fastest, multi-layer fallback)
sbar.add("item", "my_widget", {
  icon = c_bridge.icons.get("apple", icon_for("apple", "")),
  label = "Menu"
})
```

### Adding Custom Icon to state.json

```json
{
  "icons": {
    "custom_app": "󰊠",
    "my_widget": ""
  }
}
```

### Using in Control Panel

1. Open control panel
2. Navigate to Icons tab
3. Use search: type "apple" to find all apple-related icons
4. Click icon to:
   - Copy to clipboard
   - Assign to selected widget
   - Preview in bar

### App Icon Customization

Edit `icon_map.json`:

```json
{
  "My Custom App": "󰊠",
  "Another App": ""
}
```

Or use Control Panel → Icons → App Icons section.

---

## Icon Resolution Flow

```
User assigns icon name (e.g., "apple")
    ↓
1. Check C bridge icon_manager
    ├─ Found → Return glyph ()
    └─ Not found ↓
2. Check state.json icons
    ├─ Found → Return glyph
    └─ Not found ↓
3. Check modules/icons.lua
    ├─ Found → Return glyph
    └─ Not found ↓
4. Use fallback parameter
    ├─ Provided → Use fallback
    └─ Not provided → Use empty string ""
```

---

## Adding New Icons

### Option 1: Add to C icon_manager

Edit `helpers/icon_manager.c`:

```c
static const Icon builtin_icons[] = {
    {"my_icon", "󰊠", "category", 0},
    // ... existing icons
};
```

Rebuild: `cd helpers && make install`

### Option 2: Add to icon_map.json

```json
{
  "my_icon": "󰊠"
}
```

No rebuild needed!

### Option 3: Add to state.json

```json
{
  "icons": {
    "my_icon": "󰊠"
  }
}
```

Reload: `sketchybar --reload`

---

## Finding Nerd Font Glyphs

### Online Resources
- [Nerd Fonts Cheat Sheet](https://www.nerdfonts.com/cheat-sheet)
- [Font Awesome Gallery](https://fontawesome.com/icons)
- [Material Design Icons](https://materialdesignicons.com/)

### Using Icon Browser (Recommended)
```bash
~/.config/sketchybar/gui/bin/icon_browser
```

### Command Line Search
```bash
~/.config/sketchybar/bin/icon_manager search apple
~/.config/sketchybar/bin/icon_manager list system
~/.config/sketchybar/bin/icon_manager categories
```

---

## Troubleshooting

### Icon Not Displaying

1. **Check font is installed**:
   ```bash
   fc-list | grep "Hack Nerd"
   ```

2. **Verify icon exists**:
   ```bash
   ~/.config/sketchybar/bin/icon_manager get apple
   ```

3. **Check SketchyBar item**:
   ```bash
   sketchybar --query item_name
   ```

4. **Reload bar**:
   ```bash
   sketchybar --reload
   ```

### Icon Shows as Box/Question Mark

- Font not installed or not loaded by system
- Wrong unicode codepoint
- SketchyBar using different font

**Fix**: Ensure Hack Nerd Font is installed and set correct font in configuration:

```lua
["icon.font"] = "Hack Nerd Font:Bold:16.0"
```

### Icon Changes Unexpectedly

- Script overwriting icon value
- State changing icon
- App icon being replaced

**Fix**: Check script execution order and use icon_for() for consistent fallback.

---

## Best Practices

1. **Use C bridge for frequently-accessed icons** (10x faster)
2. **Define custom icons in icon_map.json** (no rebuild needed)
3. **Use semantic naming** (`apple` not `f179`)
4. **Always provide fallback** in icon_for() calls
5. **Test icons after adding** with icon_manager CLI
6. **Keep icon_map.json** organized by category
7. **Document custom icons** in comments

---

## Related Documentation

- [Control Panel Guide](CONTROL_PANEL_V2.md) - Icon Gallery tab
- [Architecture Analysis](architecture/CODE_ANALYSIS.md) - Icon system design
- [Icon Fixes Summary](troubleshooting/ICON_FIXES_SUMMARY.md) - Common issues

---

**Generated:** November 17, 2025
**Component:** barista v2.0
**Maintainer:** scawful
