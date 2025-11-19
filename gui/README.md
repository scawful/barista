# GUI Components

This directory contains the Objective-C GUI applications for Barista.

## Directory Structure

```
gui/
├── src/
│   ├── main.m                    # Application entry point
│   ├── core/                     # Core application components
│   │   ├── ConfigurationManager  # Shared state management
│   │   ├── AppDelegate           # Application lifecycle
│   │   └── MainWindowController  # Main window coordinator
│   └── tabs/                     # Tab view controllers
│       ├── AppearanceTabViewController
│       ├── WidgetsTabViewController
│       ├── SpacesTabViewController
│       ├── IconsTabViewController
│       ├── ThemesTabViewController
│       ├── ShortcutsTabViewController
│       ├── IntegrationsTabViewController
│       ├── LaunchAgentsTabViewController
│       ├── DebugTabViewController
│       ├── PerformanceTabViewController
│       └── AdvancedTabViewController
├── icon_browser.m                # Standalone icon browser
├── help_center.m                 # Standalone help center
└── CMakeLists.txt                # Build configuration
```

## Building

### Quick Rebuild (GUI only)

From the project root:
```bash
./rebuild_gui.sh
```

Or from this directory:
```bash
cd /path/to/barista
cmake --build build --target config_menu icon_browser help_center
```

### Clean Rebuild

```bash
./rebuild_gui.sh clean
```

### Full Rebuild (Everything)

From the project root:
```bash
./rebuild.sh
```

## Components

### config_menu

The unified configuration window with 11 tabs:
- **Appearance** - Bar appearance settings with live preview
- **Widgets** - Widget management and configuration
- **Spaces** - Space customization with icon browser integration
- **Icons** - Icon library with search and browser integration
- **Themes** - Theme switcher with preview
- **Shortcuts** - Keyboard shortcuts viewer/editor
- **Integrations** - External integrations (Yaze, Emacs, halext)
- **Launch Agents** - Launch agent management
- **Debug** - Debug tools and diagnostics
- **Performance** - Performance statistics
- **Advanced** - Raw JSON editor

### icon_browser

Standalone icon browser application for browsing and selecting Nerd Font icons.

### help_center

Standalone help center application for viewing documentation and help content.

## Architecture

The GUI uses a modular architecture:

1. **Core Components** (`src/core/`)
   - `ConfigurationManager` - Singleton for state management
   - `AppDelegate` - Application lifecycle
   - `MainWindowController` - Main window with tab view

2. **Tab View Controllers** (`src/tabs/`)
   - Each tab is a separate view controller
   - All tabs share the `ConfigurationManager` singleton
   - Tabs can be easily added, removed, or modified independently

3. **Build System**
   - CMake-based build system
   - Organized file structure for maintainability
   - Easy to extend with new tabs or features

## Development

### Adding a New Tab

1. Create new files in `src/tabs/`:
   - `NewTabViewController.h`
   - `NewTabViewController.m`

2. Add to `CMakeLists.txt`:
   ```cmake
   src/tabs/NewTabViewController.m
   src/tabs/NewTabViewController.h
   ```

3. Import in `MainWindowController.m`:
   ```objc
   #import "NewTabViewController.h"
   ```

4. Add tab to window in `MainWindowController.m`:
   ```objc
   self.newTab = [[NewTabViewController alloc] init];
   NSTabViewItem *newItem = [[NSTabViewItem alloc] initWithIdentifier:@"newTab"];
   newItem.label = @"New Tab";
   newItem.viewController = self.newTab;
   [self.tabView addTabViewItem:newItem];
   ```

### Modifying Existing Tabs

Each tab is self-contained in its own files. Simply edit the corresponding files in `src/tabs/` and rebuild.

## Troubleshooting

### Build Errors

1. Clean and rebuild:
   ```bash
   ./rebuild_gui.sh clean
   ```

2. Check CMake configuration:
   ```bash
   cmake -B build -S .
   ```

3. Check for missing dependencies:
   - CMake 3.20+
   - Xcode Command Line Tools
   - Cocoa framework (macOS only)

### Import Errors

Make sure all imports use the correct paths. The build system includes:
- `src/core/` for core components
- `src/tabs/` for tab view controllers

All imports should use just the filename (e.g., `#import "ConfigurationManager.h"`), not paths.

