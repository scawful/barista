# Pre-Setup Checklist for Work MacBook

## Before You Start

### 1. Check Corporate Policies ⚠️

**Important:** Verify your company's policies on:
- Installing third-party software
- Using Homebrew
- Modifying system settings (Accessibility, Screen Recording)
- Running launch agents
- SSH configuration

**Questions to answer:**
- ✅ Is Homebrew allowed?
- ✅ Can you install software from GitHub?
- ✅ Are you allowed to modify Accessibility settings?
- ✅ Can you run custom launch agents?
- ✅ Is SSH configuration restricted?

### 2. Backup Current Setup

```bash
# Backup existing SketchyBar config (if any)
if [ -d ~/.config/sketchybar ]; then
  cp -r ~/.config/sketchybar ~/.config/sketchybar.backup.$(date +%Y%m%d)
fi

# Backup SSH config
cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d)

# Backup launch agents
if [ -d ~/Library/LaunchAgents ]; then
  cp -r ~/Library/LaunchAgents ~/Library/LaunchAgents.backup.$(date +%Y%m%d)
fi
```

### 3. Verify Prerequisites

```bash
# Check macOS version (needs 13+)
sw_vers

# Check if Homebrew is installed
which brew || echo "⚠️  Homebrew not installed"

# Check existing installations
which sketchybar || echo "⚠️  SketchyBar not installed"
which yabai || echo "ℹ️  Yabai not installed (optional)"
which skhd || echo "ℹ️  skhd not installed (optional)"
which lua || echo "⚠️  Lua not installed"
which jq || echo "⚠️  jq not installed"
which cmake || echo "⚠️  CMake not installed"
```

### 4. Test Installation Method

**Option A: Homebrew (Recommended)**
```bash
# Test if you can create a tap
brew tap scawful/test-tap 2>&1 | head -5

# Check if you can install from GitHub
brew install --dry-run felixkratz/formulae/sketchybar
```

**Option B: Git Clone (Fallback)**
```bash
# Test git access
git clone --depth 1 https://github.com/scawful/barista /tmp/barista-test
rm -rf /tmp/barista-test
```

### 5. Check System Permissions

**Before installation, verify you can:**
- ✅ Grant Accessibility permissions
- ✅ Grant Screen Recording (if using Yabai)
- ✅ Create files in `~/.config/`
- ✅ Create launch agents in `~/Library/LaunchAgents/`

**Test:**
```bash
# Test config directory access
mkdir -p ~/.config/test && rmdir ~/.config/test && echo "✅ Config dir writable"

# Test launch agents directory
mkdir -p ~/Library/LaunchAgents/test && rmdir ~/Library/LaunchAgents/test && echo "✅ LaunchAgents writable"
```

### 6. Network & Proxy Considerations

**If behind corporate proxy:**
```bash
# Check proxy settings
echo $http_proxy
echo $https_proxy
echo $HTTP_PROXY
echo $HTTPS_PROXY

# Test GitHub access
curl -I https://github.com/scawful/barista 2>&1 | head -3

# Test Homebrew access
curl -I https://raw.githubusercontent.com 2>&1 | head -3
```

**If proxy is required:**
- Configure Homebrew proxy: `export HOMEBREW_CURL_OPTIONS="--proxy http://proxy:port"`
- Configure git proxy: `git config --global http.proxy http://proxy:port`
- May need to configure in `~/.gitconfig` or `~/.ssh/config`

### 7. Disk Space Check

```bash
# Check available disk space (need ~500MB)
df -h ~ | tail -1

# Check if you have space for:
# - Barista config: ~50MB
# - Build artifacts: ~200MB
# - Homebrew packages: ~300MB
```

### 8. Review Current Workflows

**Document what you currently use:**
- ✅ Current terminal setup
- ✅ Current editor/IDE configuration
- ✅ Current SSH connections
- ✅ Current build systems
- ✅ Current project locations

**This helps with:**
- Migrating existing configs
- Avoiding conflicts
- Customizing Barista to match your workflow

## Installation Strategy

### Recommended: Staged Installation

**Phase 1: Minimal Setup (Day 1)**
```bash
# Install with minimal profile
# Test basic functionality
# Verify no conflicts with existing tools
```

**Phase 2: Add Integrations (Day 2-3)**
```bash
# Enable C++ development tools
# Configure SSH connections
# Add Google-specific integrations
```

**Phase 3: Customization (Week 1)**
```bash
# Customize widgets
# Add custom menu items
# Fine-tune appearance
```

### Installation Commands

**Option 1: Homebrew (Recommended)**
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

**Option 2: Git Clone (More Control)**
```bash
# Clone to config directory
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar

# Install
./install.sh

# Setup permissions
./helpers/setup_permissions.sh
```

## Post-Installation Verification

### 1. Basic Functionality

```bash
# Check SketchyBar is running
pgrep -x sketchybar && echo "✅ SketchyBar running" || echo "❌ Not running"

# Check if bar is visible
# Look at your menu bar - should see widgets

# Test reload
sketchybar --reload && echo "✅ Reload successful"
```

### 2. Widgets

```bash
# Check widgets are visible
# Should see: clock, battery, system_info, etc.

# Test widget updates
# Click on widgets to see popups
```

### 3. Menu System

```bash
# Test control panel
# Shift + Click Apple menu icon
# Or: ~/.config/sketchybar/bin/config_menu_v2
```

### 4. Integrations

```bash
# Check C++ dev integration
~/.config/sketchybar/helpers/cpp_project_switch.sh list

# Check SSH connections
cat ~/.ssh/config | grep "^Host " | head -5

# Test Google integrations
# Open menu: Apple Menu > Google C++
```

## Common Issues & Solutions

### Issue: Homebrew Installation Fails

**Solution:**
```bash
# Check network/proxy
brew doctor

# Try git clone method instead
git clone https://github.com/scawful/barista ~/.config/sketchybar
```

### Issue: Permissions Not Working

**Solution:**
```bash
# Run permission setup script
~/.config/sketchybar/helpers/setup_permissions.sh

# Manually grant in System Settings
# System Settings > Privacy & Security > Accessibility
```

### Issue: Widgets Not Showing

**Solution:**
```bash
# Check state.json
cat ~/.config/sketchybar/state.json | jq '.widgets'

# Enable widgets
# Edit state.json or use control panel
```

### Issue: Build Scripts Fail

**Solution:**
```bash
# Check script permissions
chmod +x ~/.config/sketchybar/plugins/*.sh
chmod +x ~/.config/sketchybar/helpers/*.sh

# Check dependencies
which jq lua cmake
```

### Issue: SSH Connections Not Loading

**Solution:**
```bash
# Verify SSH config format
cat ~/.ssh/config

# Check file permissions
ls -la ~/.ssh/config

# Manually configure in state.json
```

## Work-Specific Considerations

### 1. Corporate VPN

**If using VPN:**
- May need to configure SSH connections through VPN
- GCP console may require VPN
- CodeSearch/Gerrit may require VPN

**Test:**
```bash
# Test internal tools
curl -I https://critique.corp.google.com 2>&1 | head -3
curl -I https://cs.corp.google.com 2>&1 | head -3
```

### 2. Firewall Rules

**May need to allow:**
- Homebrew package downloads
- GitHub access
- SSH connections
- Local network services

### 3. Security Software

**May interfere with:**
- Launch agents
- Accessibility permissions
- Script execution

**Check:**
- Corporate antivirus/security software
- May need to whitelist Barista directories

### 4. Network Restrictions

**If restricted:**
- May need to use git clone method
- May need to download dependencies manually
- May need to configure proxy

## Rollback Plan

### If Something Goes Wrong

**Quick Disable:**
```bash
# Stop SketchyBar
brew services stop sketchybar
# Or: launchctl bootout gui/$(id -u)/homebrew.mxcl.sketchybar

# Remove launch agent
launchctl bootout gui/$(id -u)/dev.barista.control
rm ~/Library/LaunchAgents/dev.barista.control.plist
```

**Full Rollback:**
```bash
# Restore backups
cp -r ~/.config/sketchybar.backup.* ~/.config/sketchybar
cp ~/.ssh/config.backup.* ~/.ssh/config
cp -r ~/Library/LaunchAgents.backup.* ~/Library/LaunchAgents

# Uninstall (Homebrew)
brew uninstall barista

# Or remove (Git Clone)
rm -rf ~/.config/sketchybar
```

## Testing Checklist

Before considering setup complete:

- [ ] SketchyBar starts on login
- [ ] All widgets visible and updating
- [ ] Control panel opens
- [ ] Menu items work
- [ ] C++ build status widget works
- [ ] SSH connections load correctly
- [ ] Google integrations accessible
- [ ] No conflicts with existing tools
- [ ] Permissions granted correctly
- [ ] Updates work (test with `barista-update`)

## Recommended First Steps

1. **Start with minimal profile**
   ```json
   {"profile": "minimal"}
   ```

2. **Test basic functionality**
   - Verify bar appears
   - Test widgets
   - Test control panel

3. **Add one integration at a time**
   - Start with C++ dev
   - Then SSH
   - Then Google C++

4. **Customize gradually**
   - Don't change everything at once
   - Test after each change

5. **Document your customizations**
   - Keep notes on what you changed
   - Save custom configs
   - Document any workarounds

## Support Resources

- **Documentation:** `docs/GOOGLE_CPP_WORKFLOWS.md`
- **Installation Guide:** `docs/INSTALLATION_GUIDE.md`
- **Troubleshooting:** Check logs in `~/Library/Logs/sketchybar/`
- **GitHub Issues:** For bugs or questions

## Final Recommendations

1. **Start Small:** Begin with minimal setup, add features gradually
2. **Test Thoroughly:** Verify each component before moving on
3. **Keep Backups:** Always have a rollback plan
4. **Document Changes:** Note what works and what doesn't
5. **Ask for Help:** Don't hesitate to check documentation or open issues

---

**Ready to install?** Follow the installation guide and use this checklist to verify each step!

