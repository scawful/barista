# Barista Migration Guide

This document explains how to migrate to Barista and the different deployment strategies available.

## Architecture

- **`~/Code/barista`** — Source of truth (git repository)
- **`~/.config/sketchybar`** — Deployed configuration (what sketchybar actually loads)

The `sketchybar` executable (installed via Homebrew) loads its configuration from `~/.config/sketchybar`.

## Migration Options

### Option 1: Deploy Script (Recommended)

The deploy script copies files from the source repo to the config directory, keeping them independent. This is the preferred approach as it:
- Keeps your git repo clean from runtime artifacts
- Allows editing either location without affecting the other
- Provides dry-run preview before changes

```bash
cd ~/Code/barista

# Preview what would be synced
./deploy.sh --dry-run

# Deploy and restart sketchybar
./deploy.sh

# Deploy without restarting
./deploy.sh --no-restart
```

The deploy script excludes development files (`.git`, `build/`, `.context/`, `__pycache__/`, etc.) and uses rsync with `--delete` to keep destinations in sync.

### Option 2: Symlink (Simple but Coupled)

Symlink the config directory directly to the repo. Simpler but means any file changes affect both locations.

```bash
# Remove existing config (backup first if needed)
rm -rf ~/.config/sketchybar

# Create symlink
ln -s ~/Code/barista ~/.config/sketchybar

# Restart sketchybar
brew services restart sketchybar
```

**Downside**: Build artifacts, `.git/`, and development files become visible to sketchybar.

## Quick Start

For a fresh machine:

```bash
# Clone the repo
git clone https://github.com/scawful/barista.git ~/Code/barista

# Deploy to config directory
cd ~/Code/barista
./deploy.sh

# Verify sketchybar is running
brew services list | grep sketchybar
```

## Work Machine Setup (No Binary Compilation)

For machines where compiling binaries requires approval:

```bash
# Set Lua-only mode
export BARISTA_LUA_ONLY=1

# Install TUI dependencies
pip install textual pydantic pyyaml

# Use the TUI for configuration
./bin/barista
```

See `docs/guides/TUI_CONFIGURATION.md` for detailed TUI usage.

## Environment Variables

Barista supports these environment overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `BARISTA_CONFIG_DIR` | `~/.config/sketchybar` | Config directory |
| `BARISTA_CODE_DIR` | `~/Code` | Code projects root |
| `BARISTA_SCRIPTS_DIR` | `~/.config/scripts` | Helper scripts location |
| `BARISTA_LUA_ONLY` | unset | Skip C helpers when set |

## Troubleshooting

**Sketchybar not loading config:**
```bash
# Check if config exists
ls -la ~/.config/sketchybar/

# Check sketchybar status
brew services list | grep sketchybar

# Manual restart
brew services restart sketchybar
```

**Permission issues:**
```bash
# Ensure scripts are executable
chmod +x ~/.config/sketchybar/plugins/*.sh
chmod +x ~/.config/sketchybar/bin/*
```

**Check logs:**
```bash
# View sketchybar output
tail -f /tmp/sketchybar_*.log
```

---

## Historical Progress Log

### 2025-12-16
- Created `deploy.sh` for rsync-based deployment
- Added Python TUI configuration tool (`tui/`)
- Added environment variable overrides to `main.lua` and `modules/state.lua`
- Reorganized docs into subdirectories

### 2025-11-18
- Sync audit of `~/Code/barista` and `~/Code/sketchybar`
- Control Panel + Helper parity established
- Unified Control Center implementation
- Widget + System Panel alignment
