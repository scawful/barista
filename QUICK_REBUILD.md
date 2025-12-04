# Quick Rebuild Guide

Barista now has organized code structure and easy rebuild scripts.

## Quick Commands

### Rebuild Everything
```bash
./rebuild.sh
```

### Rebuild GUI Only
```bash
./rebuild_gui.sh
```

### Clean Rebuild (Everything)
```bash
./rebuild.sh clean
```

### Rebuild Specific Components
```bash
./rebuild.sh gui      # GUI components only
./rebuild.sh helpers  # Helper binaries only
```

## New Code Organization

### GUI Structure
```
gui/
├── src/
│   ├── main.m              # Entry point
│   ├── core/               # Core components
│   │   ├── ConfigurationManager
│   │   ├── AppDelegate
│   │   └── MainWindowController
│   └── tabs/               # Tab view controllers (11 tabs)
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
├── icon_browser.m
├── help_center.m
└── CMakeLists.txt
```

### Benefits
- ✅ Organized by function (core vs tabs)
- ✅ Easy to find and modify components
- ✅ Simple rebuild scripts
- ✅ Clear separation of concerns

## Build Output

All binaries are built to: `build/bin/`

After building, you can:
- Run: `./build/bin/config_menu`
- Install: `cp build/bin/* ~/.config/sketchybar/bin/`

## Troubleshooting

If build fails:
1. Clean rebuild: `./rebuild.sh clean`
2. Check CMake: `cmake -B build -S .`
3. Check dependencies: `cmake --version`, `clang --version`

