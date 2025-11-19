# Building Barista

Barista uses CMake for building all components. This document describes the build process.

## Prerequisites

- CMake 3.20 or later
- Clang/LLVM (comes with Xcode Command Line Tools)
- macOS 13.0 or later

## Quick Start

```bash
# Configure and build
cmake -B build -S .
cmake --build build

# Or use CMake presets
cmake --preset default
cmake --build --preset default
```

## Build Configurations

### Debug Build

```bash
cmake --preset debug
cmake --build --preset debug
```

### Release Build

```bash
cmake --preset release
cmake --build --preset release
```

## Project Structure

```
barista/
├── CMakeLists.txt              # Root CMake configuration
├── helpers/
│   ├── CMakeLists.txt          # C/C++ helper binaries
│   ├── event_providers/
│   │   └── CMakeLists.txt      # Event provider binaries
│   └── menus/
│       └── CMakeLists.txt      # Menu binaries
└── gui/
    └── CMakeLists.txt          # Objective-C GUI applications
```

## Components Built

### Helper Binaries (C/C++)

- `clock_widget` - Clock widget
- `system_info_widget` - System information widget
- `space_manager` - Space management
- `submenu_hover` - Submenu hover handling
- `popup_anchor` - Popup anchoring
- `popup_hover` - Popup hover effects
- `popup_manager` - Popup management
- `popup_guard` - Popup guard
- `icon_manager` - Icon management
- `state_manager` - State management
- `widget_manager` - Widget management
- `menu_renderer` - Menu rendering
- `menu_action` - Menu actions (C++)

### Event Providers

- `cpu_load` - CPU load monitoring
- `network_load` - Network load monitoring

### Menu Binaries

- `menus` - Menu system

### GUI Applications (Objective-C)

- `config_menu_v2` - Main configuration panel
- `config_menu_enhanced` - Enhanced configuration panel
- `icon_browser` - Icon browser
- `help_center` - Help center

## Installation

After building, binaries are located in `build/bin/`. To install:

```bash
# Copy binaries to installation directory
cp build/bin/* ~/.config/sketchybar/bin/
```

Or use the provided install script:

```bash
./install.sh
```

## Development

### Using CMake Presets

CMake presets are defined in `CMakePresets.json`:

```bash
# List available presets
cmake --list-presets

# Configure with preset
cmake --preset debug

# Build with preset
cmake --build --preset debug
```

### IDE Integration

#### Emacs

The project includes `.dir-locals.el` for Emacs configuration. It sets up:
- Compile command using CMake
- Flycheck include paths
- Company-clang arguments

#### VS Code / Cursor

The project includes `.clangd` for clangd language server support.

#### Xcode

Generate Xcode project:

```bash
cmake -B build -G Xcode
open build/Barista.xcodeproj
```

## Troubleshooting

### CMake not found

Install via Homebrew:

```bash
brew install cmake
```

### Build errors

1. Clean build directory:
   ```bash
   rm -rf build
   cmake -B build -S .
   cmake --build build
   ```

2. Check compiler:
   ```bash
   clang --version
   ```

3. Check CMake version:
   ```bash
   cmake --version
   ```

## Migration from Makefiles

The project previously used Makefiles. The CMake build system replaces:
- `helpers/makefile` → `helpers/CMakeLists.txt`
- `gui/Makefile` → `gui/CMakeLists.txt`
- `helpers/event_providers/makefile` → `helpers/event_providers/CMakeLists.txt`
- `helpers/menus/makefile` → `helpers/menus/CMakeLists.txt`

Old Makefiles are kept for reference but are no longer used by the build system.

