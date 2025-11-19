# Barista Quick Reference

## Installation

### Homebrew (Recommended)
```bash
brew tap scawful/barista
brew install barista
~/.config/sketchybar/helpers/setup_permissions.sh
brew services start sketchybar
```

### Git Clone
```bash
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar && ./install.sh
```

## Updates

### Homebrew
```bash
brew upgrade barista
```

### Git Clone
```bash
~/.config/sketchybar/bin/barista-update
```

## Permissions

```bash
~/.config/sketchybar/helpers/setup_permissions.sh
```

**Required:**
- System Settings > Privacy & Security > Accessibility
  - SketchyBar, Yabai, skhd
- System Settings > Privacy & Security > Screen Recording
  - Yabai (if using)

## Launch Agent

```bash
# Install
~/.config/sketchybar/bin/install-launch-agent

# Manage
~/.config/sketchybar/launch_agents/barista-launch.sh {start|stop|restart|status}
```

## Work Profile (Google)

### Enable
Edit `~/.config/sketchybar/state.json`:
```json
{
  "profile": "work",
  "integrations": {
    "google": {"enabled": true}
  }
}
```

### Add Custom Programs
Edit `~/.config/sketchybar/profiles/work.lua`:
```lua
profile.paths = {
  custom_tool = "/path/to/tool",
}

profile.custom_menu_items = {
  {
    type = "item",
    name = "menu.google.custom_tool",
    icon = "󰨞",
    label = "Custom Tool",
    action = profile.paths.custom_tool,
    section = "menu.google.section",
  },
}
```

## Common Commands

```bash
# Reload configuration
sketchybar --reload

# Open control panel
~/.config/sketchybar/bin/config_menu_v2
# Or: Shift + Click Apple menu icon

# Check status
brew services list

# View logs
tail -f ~/Library/Logs/sketchybar/sketchybar.log
```

## File Locations

- **Configuration:** `~/.config/sketchybar/`
- **State:** `~/.config/sketchybar/state.json`
- **Profiles:** `~/.config/sketchybar/profiles/`
- **Themes:** `~/.config/sketchybar/themes/`
- **Backups:** `~/.config/sketchybar.backup.*`

## Troubleshooting

```bash
# Rebuild components
cd ~/.config/sketchybar
rm -rf build
cmake -B build -S . && cmake --build build

# Restore from backup
cp -r ~/.config/sketchybar.backup.YYYYMMDD_HHMMSS/* ~/.config/sketchybar/

# Check permissions
~/.config/sketchybar/helpers/setup_permissions.sh
```

## Documentation

- [Release Strategy](docs/RELEASE_STRATEGY.md)
- [Installation Guide](docs/INSTALLATION_GUIDE.md)
- [Release Summary](docs/RELEASE_SUMMARY.md)

