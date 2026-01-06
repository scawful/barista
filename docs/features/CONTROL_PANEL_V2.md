# SketchyBar Control Panel V2

A comprehensive macOS native control panel for managing your SketchyBar configuration with a modern tabbed interface.

## Features

### Six Specialized Tabs

#### 1. Appearance Tab
- **Bar Height**: Adjust status bar height (20-50px)
- **Corner Radius**: Control bar corner rounding (0-16px)
- **Blur Radius**: Configure backdrop blur effect (0-80px)
- **Widget Scale**: Fine-tune widget sizing (0.85-1.25x)
- **Bar Color**: Visual color picker with hex input
- **Live Preview**: See changes in real-time before applying

#### 2. Widgets Tab
- Toggle visibility for all widgets:
  - Clock
  - Battery
  - Network
  - System Info
  - Volume
  - Yabai Status
- Per-widget color customization
- Instant apply with live reload

#### 3. Spaces Tab
- **Per-Space Customization**: Configure each workspace individually
- **Custom Icons**: Assign unique icons to spaces (1-10)
- **Layout Modes**: Set default layout per space:
  - BSP (Binary Space Partitioning)
  - Stack
  - Float
- **Visual Feedback**: Real-time icon preview

#### 4. Icons Tab
- **Searchable Library**: 40+ curated Nerd Font icons
- **Categories**: System, Development, Files, Apps, Navigation, Window Management
- **Live Preview**: Large glyph display with instant search
- **One-Click Copy**: Copy icon to clipboard
- **Integration Ready**: Icons optimized for SketchyBar widgets

#### 5. Integrations Tab
Three major integrations with room for expansion:

##### Yaze (ROM Hacking)
- Enable/disable integration
- Configure build directory
- Manage recent ROMs
- Quick launch to editor

##### Emacs
- Workspace name customization
- Recent org-mode files tracking
- Deep integration with org-mode workflows

##### halext-org (Future Ready)
- **Server URL Configuration**: Connect to your halext-org instance
- **API Key Management**: Secure authentication
- **Sync Interval**: Control refresh frequency (default: 5 minutes)
- **Feature Toggles**:
  - Task management display
  - Calendar event integration
  - LLM suggestion widgets
- **Connection Testing**: Verify server connectivity
- **Future Expansion Points**:
  - Quick notes capture
  - Advanced search
  - Project management
  - Custom workflows

#### 6. Advanced Tab
- **Raw JSON Editor**: Direct state file editing
- **Syntax Highlighting**: Readable formatted JSON
- **Save/Reload**: Manual control over configuration
- **Power User Features**: Full access to all settings
- **Scripts Directory Override**: Point to a custom scripts path used by GUI helpers
- **Backup/Restore**: (Planned)

## Architecture

### Technology Stack
- **Language**: Objective-C
- **Framework**: Cocoa (native macOS APIs)
- **Memory Management**: ARC (Automatic Reference Counting)
- **Persistence**: JSON state file at `~/.config/sketchybar/state.json`
- **IPC**: Direct file I/O with Lua state management

### Design Principles
1. **Persistent Application**: Stays running in Dock, doesn't quit on window close
2. **Always on Top**: Floating window level for easy access
3. **Multi-Space Aware**: Window available across all spaces
4. **Live Updates**: Changes apply immediately with instant feedback
5. **Graceful Fallbacks**: Works even when integrations are disabled

### Window Configuration
- **Size**: 950x750 (resizable)
- **Minimum Size**: 850x650
- **Position**: Centered on launch
- **Level**: NSFloatingWindowLevel
- **Collection Behavior**: CanJoinAllSpaces + FullScreenAuxiliary

## Usage

### Launch Methods

#### 1. Shift-Click Apple Menu
The primary way to access the control panel:
```bash
# Simply Shift + Click the Apple menu icon in your bar
```

#### 2. Command Line
```bash
~/.config/sketchybar/gui/bin/config_menu_v2
```

#### 3. Programmatic Launch
```lua
-- From sketchybar configuration
os.execute("~/.config/sketchybar/gui/bin/config_menu_v2 &")
```

### Building from Source
```bash
cd ~/.config/sketchybar/gui
make config_v2
```

Or build all GUI tools:
```bash
cd ~/.config/sketchybar/gui
make all
```

### Configuration File Structure

The control panel reads/writes to `~/.config/sketchybar/state.json`:

```json
{
  "appearance": {
    "bar_height": 28,
    "corner_radius": 0,
    "bar_color": "0xC021162F",
    "blur_radius": 30,
    "widget_scale": 1.0
  },
  "widgets": {
    "clock": true,
    "battery": true,
    "network": true,
    "system_info": true,
    "volume": true
  },
  "space_icons": {
    "1": "",
    "2": "",
    "3": "󰊕"
  },
  "space_modes": {
    "1": "bsp",
    "2": "stack",
    "3": "float"
  },
  "integrations": {
    "yaze": {
      "enabled": true,
      "recent_roms": [],
      "build_dir": "build/bin"
    },
    "emacs": {
      "enabled": true,
      "workspace_name": "Emacs",
      "recent_org_files": []
    },
    "halext": {
      "enabled": false,
      "server_url": "",
      "api_key": "",
      "sync_interval": 300,
      "show_tasks": true,
      "show_calendar": true,
      "show_suggestions": true
    }
  }
}
```

## halext-org Integration

### Overview
halext-org is a task management and calendar system with LLM integration and Emacs compatibility. The control panel provides first-class support for this integration.

### Setup

1. **Launch Control Panel**
   ```bash
   Shift + Click Apple Menu
   ```

2. **Navigate to Integrations Tab**

3. **Configure halext-org Section**:
   - **Server URL**: Your halext-org server address (e.g., `https://halext.yourdomain.com`)
   - **API Key**: Authentication token (stored securely)
   - **Sync Interval**: How often to refresh data (300 seconds = 5 minutes)

4. **Enable Features**:
   - ✓ Show Tasks
   - ✓ Show Calendar
   - ✓ Show Suggestions

5. **Test Connection**:
   - Click "Test Connection" button
   - Verify server responds with OK status

### Menu Integration

Once configured, access halext-org from the Apple menu:

```
Apple Menu
  └─ halext-org
      ├─ View Tasks
      ├─ View Calendar
      ├─ LLM Suggestions
      ├─ ─────────────
      ├─ Refresh Data
      └─ Configure Integration
```

### API Endpoints

The halext module communicates with your server via REST:

- `GET /api/health` - Connection test
- `GET /api/tasks` - Fetch task list
- `GET /api/calendar/today` - Today's events
- `GET /api/llm/suggest?context=<context>` - Get suggestions

### Caching

To minimize server load:
- Task data cached for 5 minutes (configurable)
- Calendar events cached for 5 minutes
- Cache invalidated on manual refresh
- Cache location: `~/.config/sketchybar/cache/`

### Future Expansion

The integration is designed with extensibility in mind:

```lua
-- Planned features (commented in menu.lua)
{ type = "item", name = "menu.halext.notes", icon = "󰠮", label = "Quick Notes" },
{ type = "item", name = "menu.halext.search", icon = "", label = "Search" },
{ type = "submenu", name = "menu.halext.projects", icon = "󰉋", label = "Projects" },
```

To add custom features:
1. Extend `modules/integrations/halext.lua` with new functions
2. Add menu items in `modules/menu.lua` under `halext_items()`
3. Handle actions in `plugins/halext_menu.sh`

## Troubleshooting

### Control Panel Won't Launch
```bash
# Check build status
cd ~/.config/sketchybar/gui
make config_v2

# Check logs
tail -f /tmp/sketchybar_config_menu.log
```

### Changes Not Applying
1. Verify state file is writable:
   ```bash
   ls -la ~/.config/sketchybar/state.json
   ```

2. Reload SketchyBar:
   ```bash
   sketchybar --reload
   ```

3. Check for syntax errors in state.json:
   ```bash
   lua -e "print(require('json').decode(io.open(os.getenv('HOME') .. '/.config/sketchybar/state.json'):read('*a')))"
   ```

### halext-org Integration Issues

**Connection Failed**:
- Verify server URL is correct and accessible
- Check API key is valid
- Ensure network connectivity
- Review server logs for authentication errors

**No Data Showing**:
- Check cache files exist: `ls ~/.config/sketchybar/cache/`
- Force refresh from halext-org menu
- Verify server endpoints return valid JSON

**Slow Performance**:
- Increase sync_interval to reduce API calls
- Check server response times
- Consider local caching improvements

## Development

### Adding New Tabs

1. Create tab view controller interface:
```objc
@interface MyNewTabViewController : NSViewController
@property (strong) NSTextField *myField;
@end
```

2. Implement loadView and viewDidLoad:
```objc
@implementation MyNewTabViewController
- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // Add controls
}
@end
```

3. Add to MainWindowController:
```objc
self.myNewTab = [[MyNewTabViewController alloc] init];
NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"mynew"];
item.label = @"My New Tab";
item.viewController = self.myNewTab;
[self.tabView addTabViewItem:item];
```

### Extending Integrations

See `modules/integrations/halext.lua` as a reference implementation.

Key functions to implement:
- `get_data()` - Fetch from external source
- `format_for_menu()` - Transform data for display
- `create_menu_items()` - Generate menu structure
- `test_connection()` - Health check

## Credits

- **Design**: Inspired by macOS System Settings
- **Icons**: Nerd Fonts (https://www.nerdfonts.com/)
- **Integration**: Built for halext-org project

## License

Part of the SketchyBar configuration project.
