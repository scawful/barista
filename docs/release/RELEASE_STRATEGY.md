# Barista Release Strategy

## Executive Summary

This document outlines a comprehensive strategy for releasing Barista for use on work computers (specifically Google) with support for:
- Homebrew installation (primary method)
- Git clone installation (fallback)
- Safe update mechanism that preserves customizations
- macOS system permissions setup
- Launch agent orchestration
- Google-specific customizations (Emacs, custom programs)

## Table of Contents

1. [Installation Methods](#installation-methods)
2. [System Dependencies & Permissions](#system-dependencies--permissions)
3. [Update Strategy](#update-strategy)
4. [Launch Agent Management](#launch-agent-management)
5. [Customization Strategy](#customization-strategy)
6. [Implementation Plan](#implementation-plan)

---

## Installation Methods

### Option 1: Homebrew Tap (Recommended)

**Pros:**
- Professional distribution method
- Automatic dependency management
- Easy updates via `brew upgrade`
- Version tracking and rollback
- Works well in corporate environments

**Cons:**
- Requires maintaining a separate tap repository
- Initial setup overhead
- Need to publish releases

**Implementation:**

#### 1.1 Create Homebrew Tap Repository

```bash
# Create tap repository
gh repo create homebrew-barista --public
git clone https://github.com/scawful/homebrew-barista
cd homebrew-barista
mkdir -p Formula
```

#### 1.2 Formula Structure

**Formula/barista.rb:**

```ruby
class Barista < Formula
  desc "Brewing the perfect macOS status bar experience"
  homepage "https://github.com/scawful/barista"
  url "https://github.com/scawful/barista/archive/v2.0.0.tar.gz"
  sha256 "..." # Calculate with: shasum -a 256 archive.tar.gz
  license "MIT"
  version "2.0.0"

  depends_on "cmake" => :build
  depends_on "felixkratz/formulae/sketchybar" => :recommended
  depends_on "lua" => :recommended
  depends_on "jq" => :recommended
  depends_on "koekeishiya/formulae/yabai" => :optional
  depends_on "koekeishiya/formulae/skhd" => :optional

  def install
    # Build C components and GUI
    system "cmake", "-B", "build", "-S", ".", "-DCMAKE_BUILD_TYPE=Release"
    system "cmake", "--build", "build", "-j", Hardware::CPU.cores

    # Install configuration files
    config_dir = Pathname.new(ENV["HOME"])/".config/sketchybar"
    config_dir.mkpath

    # Copy configuration files (preserve existing if present)
    unless (config_dir/"main.lua").exist?
      cp_r Dir["*.lua"], config_dir
      cp_r "modules", config_dir
      cp_r "profiles", config_dir
      cp_r "themes", config_dir
      cp_r "plugins", config_dir
      cp_r "data", config_dir
      cp_r "launch_agents", config_dir
    end

    # Install binaries
    bin.install Dir["build/bin/*"]
    
    # Install helpers
    (config_dir/"helpers").install Dir["helpers/*.sh"]
    (config_dir/"helpers").install Dir["build/bin/*"]

    # Install documentation
    doc.install Dir["docs/**/*"]
  end

  def post_install
    # Create sketchybarrc if it doesn't exist
    config_dir = Pathname.new(ENV["HOME"])/".config/sketchybar"
    sketchybarrc = config_dir/"sketchybarrc"
    
    unless sketchybarrc.exist?
      sketchybarrc.write <<~EOF
        #!/usr/bin/env lua
        -- SketchyBar Configuration Entry Point
        local HOME = os.getenv("HOME")
        local CONFIG_DIR = HOME .. "/.config/sketchybar"
        dofile(CONFIG_DIR .. "/main.lua")
      EOF
      sketchybarrc.chmod 0755
    end

    # Create initial state.json if it doesn't exist
    state_file = config_dir/"state.json"
    unless state_file.exist?
      state_file.write <<~JSON
        {
          "profile": "minimal",
          "widgets": {
            "clock": true,
            "battery": true,
            "network": true,
            "system_info": true,
            "volume": true,
            "yabai_status": true
          },
          "appearance": {
            "bar_height": 32,
            "corner_radius": 9,
            "bar_color": "0xC021162F",
            "blur_radius": 30,
            "widget_scale": 1.0
          },
          "integrations": {
            "yaze": {"enabled": false},
            "emacs": {"enabled": false},
            "halext": {"enabled": false}
          }
        }
      JSON
    end
  end

  def caveats
    <<~EOS
      Barista has been installed to ~/.config/sketchybar

      Next steps:
      1. Grant Accessibility permissions (see: https://github.com/scawful/barista#permissions)
      2. Configure system permissions for yabai/skhd (if using)
      3. Choose a profile: edit ~/.config/sketchybar/state.json
      4. Start services:
         brew services start sketchybar
         # Optional:
         brew services start yabai
         brew services start skhd
      5. Install launch agent:
         cp ~/.config/sketchybar/launch_agents/dev.barista.control.plist ~/Library/LaunchAgents/
         launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.barista.control.plist

      Documentation: #{doc}
    EOS
  end

  test do
    # Test that binaries were installed
    assert_predicate bin/"config_menu_v2", :exist?
    assert_predicate bin/"icon_manager", :exist?
  end
end
```

#### 1.3 Installation Usage

```bash
# Add tap
brew tap scawful/barista

# Install barista
brew install barista

# Update barista
brew upgrade barista
```

### Option 2: Git Clone Installation (Fallback)

**Pros:**
- Full control over installation
- Easy to customize
- No external dependencies on Homebrew tap
- Works when Homebrew isn't available

**Cons:**
- Manual update process
- Need to handle dependencies manually
- More complex for end users

**Implementation:**

The existing `install.sh` script already supports this. Enhance it with:

1. **Update detection:**
   ```bash
   # Check for updates
   cd ~/.config/sketchybar
   git fetch origin
   if [ $(git rev-list HEAD...origin/main --count) != 0 ]; then
     echo "Updates available. Run: barista-update"
   fi
   ```

2. **Safe update script:**
   ```bash
   # barista-update script
   # Preserves user customizations
   ```

---

## System Dependencies & Permissions

### Required Dependencies

| Dependency | Installation | Required Permissions |
|------------|--------------|---------------------|
| **SketchyBar** | `brew install felixkratz/formulae/sketchybar` | Accessibility |
| **Lua** | `brew install lua` | None |
| **jq** | `brew install jq` | None |
| **CMake** | `brew install cmake` | None |
| **Yabai** (optional) | `brew install koekeishiya/formulae/yabai` | Accessibility, Screen Recording |
| **skhd** (optional) | `brew install koekeishiya/formulae/skhd` | Accessibility |

### macOS System Permissions Setup

#### 1. Accessibility Permissions

**Required for:** SketchyBar, Yabai, skhd

**Setup Script:** `helpers/setup_permissions.sh`

```bash
#!/bin/bash
# Automated permission setup for Barista

echo "Setting up macOS permissions for Barista..."

# Check Accessibility permissions
check_accessibility() {
  local app="$1"
  if ! sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT allowed FROM access WHERE service='kTCCServiceAccessibility' AND client='$app';" 2>/dev/null | grep -q 1; then
    echo "⚠️  $app needs Accessibility permissions"
    echo "   Go to: System Settings > Privacy & Security > Accessibility"
    echo "   Add: $app"
    return 1
  fi
  return 0
}

# Check Screen Recording (for Yabai)
check_screen_recording() {
  if command -v yabai &> /dev/null; then
    if ! sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
      "SELECT allowed FROM access WHERE service='kTCCServiceScreenRecording' AND client='yabai';" 2>/dev/null | grep -q 1; then
      echo "⚠️  Yabai needs Screen Recording permissions"
      echo "   Go to: System Settings > Privacy & Security > Screen Recording"
      echo "   Add: yabai"
      return 1
    fi
  fi
  return 0
}

# Check each component
check_accessibility "sketchybar" || NEEDS_SETUP=true
check_accessibility "yabai" || NEEDS_SETUP=true
check_accessibility "skhd" || NEEDS_SETUP=true
check_screen_recording || NEEDS_SETUP=true

if [ "$NEEDS_SETUP" = true ]; then
  echo ""
  echo "Please grant the required permissions and run this script again."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
  echo "✅ All permissions granted"
fi
```

#### 2. Yabai System Integrity Protection (SIP)

Yabai requires disabling System Integrity Protection (SIP) for full functionality:

```bash
# Check SIP status
csrutil status

# If enabled, user needs to:
# 1. Boot into Recovery Mode (Cmd+R on startup)
# 2. Open Terminal
# 3. Run: csrutil disable
# 4. Reboot

# Note: This is a security trade-off. Document clearly.
```

**Alternative:** Use Yabai in "simple" mode (limited functionality, no SIP changes)

#### 3. Launch Agent Permissions

Launch agents run in user context and don't need special permissions, but the applications they launch do.

### Automated Permission Check

Add to `install.sh`:

```bash
check_permissions() {
  echo_info "Checking macOS permissions..."
  
  # Run permission check script
  if [ -f "$INSTALL_DIR/helpers/setup_permissions.sh" ]; then
    bash "$INSTALL_DIR/helpers/setup_permissions.sh"
  else
    echo_warning "Permission check script not found. Please manually grant:"
    echo_warning "  - Accessibility: SketchyBar, Yabai, skhd"
    echo_warning "  - Screen Recording: Yabai (if using)"
  fi
}
```

---

## Update Strategy

### Core Principles

1. **Never overwrite user customizations**
2. **Preserve state.json, profiles, and custom themes**
3. **Merge new defaults with existing configuration**
4. **Provide rollback mechanism**
5. **Clear changelog and migration notes**

### Update Mechanism Design

#### For Homebrew Installation

```bash
# Update process
brew upgrade barista

# Post-update hook:
# 1. Backup current state.json
# 2. Merge new defaults with existing config
# 3. Preserve custom profiles
# 4. Update binaries
# 5. Rebuild if needed
```

**Post-Install Hook Script:** `helpers/post_update.sh`

```bash
#!/bin/bash
# Post-update script for Barista
# Runs after brew upgrade barista

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
BACKUP_DIR="${CONFIG_DIR}.backup.$(date +%Y%m%d_%H%M%S)"

echo "Running Barista post-update..."

# 1. Backup current configuration
if [ -d "$CONFIG_DIR" ]; then
  echo "Creating backup..."
  mkdir -p "$BACKUP_DIR"
  cp -r "$CONFIG_DIR/state.json" "$BACKUP_DIR/" 2>/dev/null || true
  cp -r "$CONFIG_DIR/profiles" "$BACKUP_DIR/" 2>/dev/null || true
  cp -r "$CONFIG_DIR/themes" "$BACKUP_DIR/" 2>/dev/null || true
fi

# 2. Merge new configuration files
# Only copy files that don't exist or are templates
merge_config_files() {
  local source_dir="$1"
  local dest_dir="$2"
  
  find "$source_dir" -type f | while read -r file; do
    rel_path="${file#$source_dir/}"
    dest_file="$dest_dir/$rel_path"
    
    # If file doesn't exist, copy it
    if [ ! -f "$dest_file" ]; then
      mkdir -p "$(dirname "$dest_file")"
      cp "$file" "$dest_file"
      echo "Added: $rel_path"
    # If it's a template file (ends in .template), merge
    elif [[ "$file" == *.template ]]; then
      echo "Template file: $rel_path (skipping merge, manual review needed)"
    fi
  done
}

# 3. Update binaries
if [ -d "$CONFIG_DIR/build" ]; then
  echo "Rebuilding components..."
  cd "$CONFIG_DIR"
  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  cp -f build/bin/* bin/ 2>/dev/null || true
fi

# 4. Check for migration needs
if [ -f "$CONFIG_DIR/helpers/migrate.sh" ]; then
  echo "Checking for configuration migrations..."
  "$CONFIG_DIR/helpers/migrate.sh"
fi

echo "✅ Update complete. Backup saved to: $BACKUP_DIR"
```

#### For Git Clone Installation

**Update Script:** `bin/barista-update`

```bash
#!/bin/bash
# Safe update script for git clone installations

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
CURRENT_BRANCH=$(cd "$CONFIG_DIR" && git rev-parse --abbrev-ref HEAD)
CURRENT_COMMIT=$(cd "$CONFIG_DIR" && git rev-parse HEAD)

echo "Updating Barista..."

# 1. Stash local changes (but preserve state.json, profiles, themes)
cd "$CONFIG_DIR"

# Create backup
BACKUP_DIR="${CONFIG_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp state.json "$BACKUP_DIR/" 2>/dev/null || true
cp -r profiles "$BACKUP_DIR/" 2>/dev/null || true
cp -r themes "$BACKUP_DIR/" 2>/dev/null || true

# 2. Fetch updates
git fetch origin

# 3. Check what changed
CHANGES=$(git log HEAD..origin/main --oneline | wc -l | tr -d ' ')

if [ "$CHANGES" -eq 0 ]; then
  echo "✅ Already up to date"
  exit 0
fi

echo "Found $CHANGES new commits"

# 4. Show changelog
echo ""
echo "Recent changes:"
git log HEAD..origin/main --oneline -10

# 5. Ask for confirmation
read -p "Update now? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Update cancelled"
  exit 0
fi

# 6. Merge updates (preserve local files)
git stash push -m "barista-update-$(date +%s)" -- \
  -- ':!state.json' ':!profiles/**' ':!themes/**' ':!*.local.lua'

# 7. Merge or rebase
if git merge-base --is-ancestor HEAD origin/main; then
  # Fast-forward possible
  git merge --ff-only origin/main
else
  # Need to merge
  git merge origin/main --no-edit || {
    echo "⚠️  Merge conflicts detected. Resolving..."
    git checkout --theirs -- '*.lua' 'modules/**' 'plugins/**' 'helpers/**'
    git checkout --ours -- 'state.json' 'profiles/**' 'themes/**'
    git add .
    git commit -m "Merge barista updates (preserved local customizations)"
  }
fi

# 8. Restore stashed changes (if any)
git stash pop || true

# 9. Rebuild if needed
if [ -f CMakeLists.txt ]; then
  echo "Rebuilding components..."
  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  cp -f build/bin/* bin/ 2>/dev/null || true
fi

# 10. Run migrations
if [ -f helpers/migrate.sh ]; then
  echo "Running migrations..."
  bash helpers/migrate.sh
fi

echo ""
echo "✅ Update complete!"
echo "   Backup saved to: $BACKUP_DIR"
echo "   Review changes: git log $CURRENT_COMMIT..HEAD"
echo ""
echo "Next steps:"
echo "  1. Review CHANGELOG.md for breaking changes"
echo "  2. Test your configuration: sketchybar --reload"
echo "  3. If issues, restore from backup: cp -r $BACKUP_DIR/* $CONFIG_DIR/"
```

### Configuration Migration System

**Migration Script:** `helpers/migrate.sh`

```bash
#!/bin/bash
# Configuration migration system
# Handles breaking changes between versions

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"
VERSION_FILE="$CONFIG_DIR/.barista_version"

# Get current version
CURRENT_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")
NEW_VERSION="2.0.0"

# Migration functions
migrate_1_0_to_2_0() {
  echo "Migrating from 1.0.x to 2.0.0..."
  
  # Example: Rename old keys
  if [ -f "$STATE_FILE" ]; then
    python3 <<EOF
import json
import sys

with open("$STATE_FILE", "r") as f:
    state = json.load(f)

# Migration logic
if "widgets" in state and "network" in state["widgets"]:
    # Migrate old network widget to new structure
    pass

# Save updated state
with open("$STATE_FILE", "w") as f:
    json.dump(state, f, indent=2)
EOF
  fi
}

# Run migrations based on version
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
  echo "Running migrations from $CURRENT_VERSION to $NEW_VERSION..."
  
  # Add version-specific migrations here
  migrate_1_0_to_2_0
  
  # Update version file
  echo "$NEW_VERSION" > "$VERSION_FILE"
  echo "✅ Migration complete"
fi
```

---

## Launch Agent Management

### Unified Launch Agent

The existing `launch_agents/barista-launch.sh` orchestrates SketchyBar, Yabai, and skhd.

### Installation

**Script:** `bin/install-launch-agent`

```bash
#!/bin/bash
# Install Barista launch agent

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
PLIST_SOURCE="$CONFIG_DIR/launch_agents/dev.barista.control.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/dev.barista.control.plist"
DOMAIN="gui/$(id -u)"

echo "Installing Barista launch agent..."

# 1. Update plist with correct paths
sed "s|\$HOME|$HOME|g" "$PLIST_SOURCE" > "$PLIST_DEST"

# 2. Load launch agent
launchctl bootstrap "$DOMAIN" "$PLIST_DEST" 2>/dev/null || \
  launchctl kickstart -kp "${DOMAIN}/dev.barista.control"

echo "✅ Launch agent installed"
echo ""
echo "The launch agent will:"
echo "  - Start SketchyBar, Yabai, and skhd on login"
echo "  - Manage all services together"
echo ""
echo "To manage manually:"
echo "  ~/.config/sketchybar/launch_agents/barista-launch.sh {start|stop|restart|status}"
```

### Launch Agent Features

1. **Unified Control:** Single command to start/stop all services
2. **Health Checks:** (Future) Monitor and restart failed services
3. **Dependency Ordering:** Start services in correct order
4. **Logging:** Centralized logging for all services

---

## Customization Strategy

### Google-Specific Customizations

#### 1. Work Profile Enhancement

**File:** `profiles/work.lua` (already exists, enhance it)

```lua
-- Work Profile (Google)
-- Enhanced with Google-specific integrations

local profile = {}

profile.name = "work"
profile.description = "Work setup for Google with Emacs integration"

-- Google-specific paths
profile.paths = {
  work_docs = os.getenv("HOME") .. "/work/docs",
  google_tools = os.getenv("HOME") .. "/google/tools",
  -- Add Google-specific program paths
}

-- Google-specific integrations
profile.integrations = {
  yaze = false,
  emacs = true,
  halext = true,
  google = true,  -- Enable Google integrations
}

-- Custom menu items for Google tools
profile.custom_menus = {
  {
    type = "item",
    name = "menu.google.gmail",
    icon = "󰬦",
    label = "Gmail",
    action = "open -a 'Google Chrome' 'https://mail.google.com'",
  },
  {
    type = "item",
    name = "menu.google.calendar",
    icon = "󰃭",
    label = "Calendar",
    action = "open -a 'Google Chrome' 'https://calendar.google.com'",
  },
  -- Add custom Google programs
  {
    type = "item",
    name = "menu.google.custom_tool",
    icon = "󰨞",
    label = "Custom Tool",
    action = os.getenv("HOME") .. "/google/tools/custom_tool",
  },
}

return profile
```

#### 2. Custom Integration Module

**File:** `modules/integrations/google.lua`

```lua
-- Google-specific integrations for Barista

local google = {}

google.enabled = false
google.config = {}

function google.init(sbar, config)
  if not config.integrations.google or not config.integrations.google.enabled then
    return
  end
  
  google.enabled = true
  google.config = config.integrations.google
  
  -- Setup Google-specific widgets/menus
  print("Google integration enabled")
end

function google.setup_menu_items(menu_items)
  if not google.enabled then
    return menu_items
  end
  
  -- Add Google menu items
  table.insert(menu_items, {
    type = "item",
    name = "menu.google.gmail",
    icon = "󰬦",
    label = "Gmail",
    action = "open -a 'Google Chrome' 'https://mail.google.com'",
  })
  
  return menu_items
end

return google
```

#### 3. Emacs Integration Enhancement

The existing `.emacs-integration.el` is good. Add Google-specific functions:

```elisp
;; Google-specific Emacs functions
(defun barista-open-google-docs ()
  "Open Google Docs"
  (interactive)
  (browse-url "https://docs.google.com"))

(defun barista-open-google-drive ()
  "Open Google Drive"
  (interactive)
  (browse-url "https://drive.google.com"))
```

#### 4. Custom Programs Integration

**File:** `helpers/google_programs.lua`

```lua
-- Integration for Google-specific programs

local google_programs = {
  -- Define custom programs
  programs = {
    {
      name = "custom_tool",
      path = os.getenv("HOME") .. "/google/tools/custom_tool",
      icon = "󰨞",
      label = "Custom Tool",
    },
    -- Add more programs as needed
  },
}

function google_programs.get_menu_items()
  local items = {}
  for _, program in ipairs(google_programs.programs) do
    if os.execute("test -f " .. program.path) == 0 then
      table.insert(items, {
        type = "item",
        name = "menu.google." .. program.name,
        icon = program.icon,
        label = program.label,
        action = program.path,
      })
    end
  end
  return items
end

return google_programs
```

### Customization Preservation

**Key Principle:** User customizations in these locations are NEVER overwritten:

- `state.json` - User configuration
- `profiles/*.lua` - Custom profiles
- `themes/*.lua` - Custom themes
- `*.local.lua` - Local overrides
- `plugins/*.local.sh` - Local plugin modifications

**Update Process:**
1. Backup all user files
2. Update core files (main.lua, modules, etc.)
3. Merge new defaults with existing config
4. Preserve all user customizations

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

- [ ] Create Homebrew tap repository
- [ ] Write Homebrew formula
- [ ] Test Homebrew installation
- [ ] Create permission setup script
- [ ] Document system requirements

### Phase 2: Update Mechanism (Week 2)

- [ ] Implement post-update hook for Homebrew
- [ ] Create `barista-update` script for git installations
- [ ] Build migration system
- [ ] Test update scenarios
- [ ] Create backup/restore mechanism

### Phase 3: Launch Agent (Week 2)

- [ ] Enhance launch agent installation script
- [ ] Test launch agent on fresh install
- [ ] Document launch agent usage
- [ ] Add health check capabilities (future)

### Phase 4: Customization (Week 3)

- [ ] Enhance work profile with Google integrations
- [ ] Create Google integration module
- [ ] Document customization process
- [ ] Create customization templates

### Phase 5: Documentation & Testing (Week 3-4)

- [ ] Write installation guide
- [ ] Create troubleshooting guide
- [ ] Test on clean macOS installation
- [ ] Test update scenarios
- [ ] Create video walkthrough (optional)

### Phase 6: Release (Week 4)

- [ ] Tag release v2.0.0
- [ ] Publish Homebrew tap
- [ ] Update README with installation instructions
- [ ] Create release notes
- [ ] Announce release

---

## Testing Checklist

### Installation Testing

- [ ] Fresh macOS installation (Ventura+)
- [ ] Existing SketchyBar configuration
- [ ] Homebrew installation
- [ ] Git clone installation
- [ ] Permission setup
- [ ] Launch agent installation

### Update Testing

- [ ] Homebrew update (brew upgrade)
- [ ] Git clone update (barista-update)
- [ ] Preserve customizations
- [ ] Handle merge conflicts
- [ ] Rollback mechanism

### Customization Testing

- [ ] Work profile with Google integrations
- [ ] Custom programs integration
- [ ] Emacs integration
- [ ] Custom themes preservation

---

## Security Considerations

### For Work Computers

1. **No Root Access Required:** All installation in user space
2. **Minimal Permissions:** Only what's necessary
3. **Audit Trail:** Log all system changes
4. **Rollback:** Easy to uninstall/rollback
5. **Documentation:** Clear security implications (SIP, etc.)

### Installation Safety

- Never modify system files
- All changes in `~/.config/sketchybar`
- Launch agents in user space only
- No network access during installation
- All scripts are readable/auditable

---

## Conclusion

This strategy provides:

1. **Professional Distribution:** Homebrew tap for easy installation
2. **Flexible Installation:** Git clone fallback for full control
3. **Safe Updates:** Preserves all user customizations
4. **System Integration:** Proper macOS permissions and launch agents
5. **Customization Support:** Easy to add Google-specific features

The implementation can be done incrementally, starting with Homebrew formula and basic update mechanism, then adding customization features.

