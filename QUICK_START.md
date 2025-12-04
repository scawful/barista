# Quick Start Guide

## Building Barista

### Using CMake (Recommended)

```bash
# Configure and build
cmake -B build -S .
cmake --build build

# Or use presets
cmake --preset release
cmake --build --preset release
```

### Using Presets

```bash
# Debug build
cmake --preset debug
cmake --build --preset debug

# Release build
cmake --preset release
cmake --build --preset release
```

## Emacs Integration

### Setup

1. The project includes `.dir-locals.el` which automatically configures:
   - Compile commands
   - Include paths
   - Language settings

2. Load Barista-specific functions:
   ```elisp
   (load-file "~/.config/sketchybar/.emacs-integration.el")
   ```

3. Use Projectile for project navigation:
   - `C-c p f` - Find file
   - `C-c p g` - Grep in project
   - `C-c p c` - Compile

### Available Functions

- `M-x barista-open-main-config` - Open main.lua
- `M-x barista-open-state-json` - Open state.json
- `M-x barista-reload-sketchybar` - Reload SketchyBar
- `M-x barista-open-control-panel` - Open control panel
- `M-x barista-open-yaze` - Open Yaze
- `M-x barista-open-halext-tasks` - Open halext-org tasks

## IDE Support

### VS Code / Cursor

The project includes `.clangd` for language server support. Install the clangd extension for:
- Code completion
- Error checking
- Go-to-definition
- Refactoring

### Xcode

Generate Xcode project:
```bash
cmake -B build -G Xcode
open build/Barista.xcodeproj
```

## Integration Configurations

### Yaze

Configuration file: `.yaze-integration.json`
- Defines paths and build information
- Menu items configuration
- Workflow settings

### halext-org

Configuration file: `.halext-integration.json`
- Feature flags
- Cache settings
- API endpoints
- Menu items

## Troubleshooting

### CMake not found
```bash
brew install cmake
```

### Build errors
```bash
# Clean and rebuild
rm -rf build
cmake -B build -S .
cmake --build build
```

### Missing dependencies
```bash
# Install via Homebrew
brew install cmake lua jq
```

## Documentation

- [BUILD.md](BUILD.md) - Detailed build instructions
- [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md) - Refactoring overview
- [docs/CMake_MIGRATION.md](docs/CMake_MIGRATION.md) - Migration guide

