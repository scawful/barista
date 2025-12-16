# Barista Release Strategy - Executive Summary

## Overview

This document summarizes the release strategy for Barista, enabling safe installation and updates on work computers (specifically Google) with support for customizations.

## Key Components

### 1. Installation Methods

**Primary: Homebrew Tap**
- Professional distribution
- Easy updates: `brew upgrade barista`
- Automatic dependency management
- Version tracking and rollback

**Fallback: Git Clone**
- Full control
- Customizable
- Update script: `bin/barista-update`

### 2. System Permissions

**Required Permissions:**
- **Accessibility:** SketchyBar, Yabai, skhd
- **Screen Recording:** Yabai (for full functionality)

**Setup Script:** `helpers/setup_permissions.sh`
- Automated permission checking
- Guides users through setup
- Opens System Settings automatically

### 3. Update Strategy

**Core Principle:** Never overwrite user customizations

**Protected Files:**
- `state.json` - User configuration
- `profiles/*.lua` - Custom profiles
- `themes/*.lua` - Custom themes
- `*.local.lua` - Local overrides
- `plugins/*.local.sh` - Local plugin modifications

**Update Mechanisms:**
- **Homebrew:** `brew upgrade barista` → runs `helpers/post_update.sh`
- **Git Clone:** `bin/barista-update` → safe merge with conflict resolution

**Backup System:**
- Automatic backups before updates
- Timestamped backup directories
- Easy rollback

### 4. Launch Agent Management

**Unified Control:** Single launch agent manages SketchyBar, Yabai, and skhd

**Installation:** `bin/install-launch-agent`

**Features:**
- Starts all services on login
- Unified start/stop/restart
- Centralized logging
- Health checks (future)

### 5. Google-Specific Customizations

**Work Profile:** `profiles/work.lua`
- Pre-configured for Google environment
- Emacs integration
- halext-org integration
- Google Workspace shortcuts

**Google Integration Module:** `modules/integrations/google.lua`
- Gmail, Calendar, Drive, Docs shortcuts
- Custom program integration
- Extensible for additional tools

**Custom Programs:**
- Add to `profiles/work.lua` → `profile.paths`
- Add menu items → `profile.custom_menu_items`
- Configure in `state.json` → `integrations.google.custom_programs`

## Quick Start for Work Computer

```bash
# 1. Install via Homebrew
brew tap scawful/barista
brew install barista

# 2. Setup permissions
~/.config/sketchybar/helpers/setup_permissions.sh

# 3. Configure work profile
# Edit ~/.config/sketchybar/state.json:
#   Set "profile": "work"
#   Enable Google integration

# 4. Add custom programs (optional)
# Edit ~/.config/sketchybar/profiles/work.lua
# Add to profile.paths and profile.custom_menu_items

# 5. Install launch agent
~/.config/sketchybar/bin/install-launch-agent

# 6. Start services
brew services start sketchybar
# Optional:
brew services start yabai
brew services start skhd
```

## Update Process

### Homebrew
```bash
brew upgrade barista
# Post-update hook automatically:
# - Backs up configuration
# - Merges new defaults
# - Preserves customizations
# - Rebuilds if needed
```

### Git Clone
```bash
~/.config/sketchybar/bin/barista-update
# Or manually:
cd ~/.config/sketchybar
git pull origin main
# Rebuild if needed
```

## File Structure

```
~/.config/sketchybar/
├── state.json              # User configuration (PRESERVED)
├── profiles/
│   ├── work.lua           # Work profile with Google integrations
│   └── *.lua              # Custom profiles (PRESERVED)
├── themes/
│   └── *.lua             # Custom themes (PRESERVED)
├── modules/
│   └── integrations/
│       └── google.lua    # Google integration module
├── helpers/
│   ├── setup_permissions.sh  # Permission setup
│   ├── post_update.sh        # Post-update hook
│   └── migrate.sh             # Configuration migrations
└── bin/
    ├── barista-update         # Update script (git clone)
    └── install-launch-agent   # Launch agent installer
```

## Safety Features

1. **Backup Before Updates:** Automatic timestamped backups
2. **Merge Strategy:** Never overwrites user files
3. **Conflict Resolution:** Automatic resolution with user file priority
4. **Rollback:** Easy restore from backups
5. **Migration System:** Handles breaking changes between versions
6. **Permission Checks:** Automated permission verification

## Customization Points

### For Google Work Environment

1. **Work Profile** (`profiles/work.lua`)
   - Pre-configured Google integrations
   - Emacs workspace
   - halext-org task management

2. **State Configuration** (`state.json`)
   ```json
   {
     "profile": "work",
     "integrations": {
       "google": {
         "enabled": true,
         "custom_programs": [...]
       }
     }
   }
   ```

3. **Custom Programs**
   - Add to `profile.paths` in work.lua
   - Add menu items to `profile.custom_menu_items`
   - Or configure in `state.json`

## Implementation Status

✅ **Completed:**
- Release strategy document
- Homebrew formula template
- Permission setup script
- Update scripts (Homebrew & Git)
- Migration system
- Launch agent installer
- Google integration module
- Enhanced work profile
- Installation guide

📋 **Next Steps:**
1. Create Homebrew tap repository (`homebrew-barista`)
2. Test Homebrew installation
3. Test update scenarios
4. Create release v2.0.0
5. Publish Homebrew tap
6. Update README with installation instructions

## Documentation

- **[Release Strategy](RELEASE_STRATEGY.md)** - Comprehensive strategy document
- **[Installation Guide](INSTALLATION_GUIDE.md)** - Step-by-step installation
- **[Control Panel Guide](CONTROL_PANEL_V2.md)** - GUI documentation
- **[Themes Guide](THEMES.md)** - Theme customization
- **[Icons & Shortcuts](ICONS_AND_SHORTCUTS.md)** - Icon management

## Support

For issues or questions:
1. Check [Troubleshooting Guide](../troubleshooting/)
2. Review [Installation Guide](INSTALLATION_GUIDE.md)
3. Check GitHub Issues

---

**Last Updated:** 2024
**Version:** 2.0.0

