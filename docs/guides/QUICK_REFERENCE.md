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
~/.config/sketchybar/helpers/post_update.sh
~/.config/sketchybar/launch_agents/barista-launch.sh restart
```

### Git Clone
```bash
~/.config/sketchybar/bin/barista-update          # Backup, merge, rebuild, restart
# If IT tools manage services:
BARISTA_SKIP_RESTART=1 ~/.config/sketchybar/bin/barista-update
```

### Repo Deploy (Separate Source Repo)
```bash
./scripts/update_repo.sh                 # Update repo + deploy
./scripts/deploy.sh --note "yabai space fixes"
./scripts/deploy_info.sh
```

### Themes & Fallbacks
```bash
BARISTA_THEME=espresso sketchybar --reload        # Quick theme switch (see themes/*.lua)
BARISTA_LUA_ONLY=1 sketchybar --reload            # Lua-only mode (no compiled helpers)
# Custom colors: create ~/.config/sketchybar/themes/theme.local.lua returning a table of overrides
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

## Profiles

### Enable a Profile
Edit `~/.config/sketchybar/state.json`:
```json
{
  "profile": "work"
}
```

### Customize Work Profile
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
- **Deploy metadata:** `~/.config/sketchybar/.barista_deploy.json`
- **Deploy history:** `~/.config/sketchybar/.deployments.log`

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

- [Pre-Setup Checklist](docs/PRE_SETUP_CHECKLIST.md) ⭐ **Read this first!**
- [Release Strategy](docs/RELEASE_STRATEGY.md)
- [Installation Guide](docs/INSTALLATION_GUIDE.md)
