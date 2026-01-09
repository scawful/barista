# Barista Installation Guide

## Quick Start

### Option 1: Homebrew (Recommended)

```bash
# Add tap
brew tap scawful/barista

# Install
brew install barista

# Setup permissions
~/.config/sketchybar/helpers/setup_permissions.sh

# Start services
brew services start sketchybar
```

### Option 2: Git Clone

```bash
# Clone repository
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar

# Install
./install.sh

# Setup permissions
./helpers/setup_permissions.sh
```

## Detailed Installation

### Prerequisites

- macOS 13+ (Ventura or later)
- Homebrew (for dependency management)
- Git (for git clone method)

### Step 1: Install Dependencies

Barista will automatically install these via Homebrew:

**Required:**
- SketchyBar (`felixkratz/formulae/sketchybar`)
- Lua (`lua`)
- jq (`jq`)
- CMake (`cmake`) - for building components

**Optional but Recommended:**
- Yabai (`koekeishiya/formulae/yabai`) - tiling window manager
- skhd (`koekeishiya/formulae/skhd`) - hotkey daemon

### Step 2: Install Barista

#### Homebrew Method

```bash
# Add the tap
brew tap scawful/barista

# Install Barista
brew install barista
```

The installer will:
1. Build all C components and GUI
2. Install configuration files to `~/.config/sketchybar`
3. Create initial `state.json` if it doesn't exist
4. Set up `sketchybarrc` entry point

#### Git Clone Method

```bash
# Clone repository
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar

# Run installer
./install.sh
```

The installer will:
1. Check and install dependencies
2. Backup existing configuration (if any)
3. Build all components using CMake
4. Let you choose a profile (minimal, personal, work, custom)
5. Start SketchyBar

### Step 3: Grant macOS Permissions

Barista requires macOS permissions for full functionality:

```bash
# Run permission setup script
~/.config/sketchybar/helpers/setup_permissions.sh
```

Or manually:

1. **System Settings > Privacy & Security > Accessibility**
   - Add: SketchyBar
   - Add: Yabai (if using)
   - Add: skhd (if using)

2. **System Settings > Privacy & Security > Screen Recording** (for Yabai)
   - Add: Yabai

3. **Yabai System Integrity Protection (SIP)** (optional, for full Yabai functionality)
   - Boot into Recovery Mode (Cmd+R on startup)
   - Open Terminal
   - Run: `csrutil disable`
   - Reboot
   - **Note:** This is a security trade-off. See [Yabai documentation](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)

### Step 4: Choose a Profile

Edit `~/.config/sketchybar/state.json`:

```json
{
  "profile": "work"  // or "minimal", "personal", or custom
}
```

Available profiles:
- **minimal**: Clean, basic setup (recommended for new users)
- **personal**: Full-featured with integrations
- **work**: Work-focused with Emacs and productivity integrations

### Step 5: Start Services

#### Using Homebrew Services

```bash
# Start SketchyBar
brew services start sketchybar

# Optional: Start Yabai and skhd
brew services start yabai
brew services start skhd
```

#### Using Launch Agent (Recommended)

The launch agent manages all services together:

```bash
# Install launch agent
~/.config/sketchybar/bin/install-launch-agent
```

The launch agent will:
- Start SketchyBar, Yabai, and skhd on login
- Manage all services together
- Provide unified control

### Step 6: Verify Installation

1. Check that SketchyBar is running:
   ```bash
   pgrep -x sketchybar
   ```

2. Reload configuration:
   ```bash
   sketchybar --reload
   ```

3. Open control panel:
   - Shift + Click the Apple menu icon
   - Or: `~/.config/sketchybar/bin/config_menu_v2`

## Customization for Work

Edit `~/.config/sketchybar/profiles/work.lua` to update integrations and paths:

```lua
profile.integrations = {
  emacs = true,
  halext = true,
  cpp_dev = true,
  ssh_cloud = true,
}

profile.paths = {
  work_docs = "/path/to/work/docs",
  code = "/path/to/src",
}
```

Then reload SketchyBar:
```bash
sketchybar --reload
```

## Updates

### Homebrew Installation

```bash
# Update Barista
brew upgrade barista

# The post-update hook will:
# - Backup your configuration
# - Merge new defaults
# - Preserve customizations
# - Rebuild if needed
```

### Git Clone Installation

```bash
# Update Barista
~/.config/sketchybar/bin/barista-update

# Or manually:
cd ~/.config/sketchybar
git pull origin main
# Rebuild if needed
cmake -B build -S . && cmake --build build
```

The update script will:
- Create a backup
- Fetch and merge updates
- Preserve your customizations (state.json, profiles, themes)
- Rebuild components if needed
- Run migrations if necessary

## Troubleshooting

### SketchyBar Not Starting

1. Check permissions:
   ```bash
   ~/.config/sketchybar/helpers/setup_permissions.sh
   ```

2. Check logs:
   ```bash
   tail -f ~/Library/Logs/sketchybar/sketchybar.log
   ```

3. Reload manually:
   ```bash
   sketchybar --reload
   ```

### Build Errors

1. Clean and rebuild:
   ```bash
   cd ~/.config/sketchybar
   rm -rf build
   cmake -B build -S .
   cmake --build build
   ```

2. Check dependencies:
   ```bash
   brew install cmake lua jq
   ```

### Permission Issues

1. Run permission check:
   ```bash
   ~/.config/sketchybar/helpers/setup_permissions.sh
   ```

2. Manually grant in System Settings:
   - Privacy & Security > Accessibility
   - Privacy & Security > Screen Recording (for Yabai)

### Update Issues

If an update breaks your configuration:

1. Restore from backup:
   ```bash
   # Find latest backup
   ls -td ~/.config/sketchybar.backup.* | head -1
   
   # Restore
   cp -r ~/.config/sketchybar.backup.YYYYMMDD_HHMMSS/* ~/.config/sketchybar/
   ```

2. Rollback Homebrew version:
   ```bash
   brew uninstall barista
   brew install barista@<previous-version>
   ```

## Uninstallation

### Homebrew

```bash
# Uninstall
brew uninstall barista

# Remove configuration (optional)
rm -rf ~/.config/sketchybar
```

### Git Clone

```bash
# Stop services
brew services stop sketchybar
brew services stop yabai
brew services stop skhd

# Remove launch agent
launchctl bootout gui/$(id -u)/dev.barista.control
rm ~/Library/LaunchAgents/dev.barista.control.plist

# Remove configuration (optional)
rm -rf ~/.config/sketchybar
```

## Next Steps

- Read the [Control Panel Guide](CONTROL_PANEL_V2.md)
- Explore [Themes](THEMES.md)
- Check [Icons & Shortcuts](ICONS_AND_SHORTCUTS.md)
- See [Troubleshooting Guide](../troubleshooting/)
