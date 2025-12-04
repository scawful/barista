# Work MacBook Setup Guide

## Quick Start for Corporate Environment

This guide is specifically tailored for setting up Barista on a work/corporate MacBook with Google C++ and SSH workflows.

## Pre-Flight Checklist

### ✅ Before Installation

1. **Verify Corporate Policies**
   - [ ] Check if Homebrew is allowed
   - [ ] Verify you can install from GitHub
   - [ ] Confirm Accessibility permissions are allowed
   - [ ] Check if launch agents are permitted

2. **System Requirements**
   - [ ] macOS 13+ (Ventura or later)
   - [ ] Admin access (for permissions)
   - [ ] Network access to GitHub
   - [ ] ~500MB free disk space

3. **Backup Current Setup**
   ```bash
   # Run backup script
   ~/.config/sketchybar/helpers/backup.sh  # If exists
   # Or manually:
   cp -r ~/.config/sketchybar ~/.config/sketchybar.backup.$(date +%Y%m%d) 2>/dev/null || true
   ```

4. **Test Network Access**
   ```bash
   # Test GitHub
   curl -I https://github.com/scawful/barista
   
   # Test Homebrew (if using)
   brew doctor
   ```

## Installation Steps

### Step 1: Choose Installation Method

**Option A: Homebrew (If Allowed)**
```bash
brew tap scawful/barista
brew install barista
```

**Option B: Git Clone (More Control, No Homebrew Required)**
```bash
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar
./install.sh
```

### Step 2: Grant Permissions

```bash
# Run automated permission setup
~/.config/sketchybar/helpers/setup_permissions.sh

# Or manually:
# System Settings > Privacy & Security > Accessibility
# Add: SketchyBar, Yabai (if using), skhd (if using)
```

### Step 3: Configure Work Profile

Edit `~/.config/sketchybar/state.json`:

```json
{
  "profile": "work",
  "integrations": {
    "cpp_dev": {
      "enabled": true,
      "project_path": "/Users/yourname/Code",
      "current_project": "default"
    },
    "ssh_cloud": {
      "enabled": true,
      "gcp_enabled": true
    },
    "google_cpp": {
      "enabled": true,
      "project_path": "/Users/yourname/google3"
    }
  },
  "widgets": {
    "cpp_build_status": true,
    "ssh_connections": true,
    "bazel_status": true
  }
}
```

### Step 4: Configure Your Projects

**C++ Projects:**
```json
{
  "integrations": {
    "cpp_dev": {
      "project_path": "/Users/yourname/Code",
      "current_project": "my-project"
    }
  }
}
```

**Google3:**
```json
{
  "integrations": {
    "google_cpp": {
      "project_path": "/Users/yourname/google3",
      "current_target": "//path/to:target"
    }
  }
}
```

**SSH Connections:**
- Automatically loaded from `~/.ssh/config`
- Or configure in state.json

### Step 5: Start Services

```bash
# Start SketchyBar
brew services start sketchybar
# Or: sketchybar --reload

# Optional: Install launch agent
~/.config/sketchybar/bin/install-launch-agent
```

## Work-Specific Configuration

### Corporate VPN Setup

If you need VPN for internal tools:

```json
{
  "integrations": {
    "google_cpp": {
      "ci_url": "https://ci.corp.google.com",
      "ci_project_id": "your-project"
    }
  }
}
```

### Proxy Configuration

If behind corporate proxy:

```bash
# For Homebrew
export HOMEBREW_CURL_OPTIONS="--proxy http://proxy:port"

# For Git
git config --global http.proxy http://proxy:port
git config --global https.proxy http://proxy:port
```

### SSH Through VPN

If SSH requires VPN:

```bash
# Configure SSH to use VPN gateway
# Edit ~/.ssh/config:
Host *.corp.google.com
  ProxyJump vpn-gateway
  User your-username
```

## Verification

### Test Basic Functionality

```bash
# 1. Check SketchyBar is running
pgrep -x sketchybar && echo "✅ Running"

# 2. Test reload
sketchybar --reload && echo "✅ Reload works"

# 3. Open control panel
~/.config/sketchybar/bin/config_menu_v2

# 4. Check widgets
# Look at menu bar - should see widgets updating
```

### Test Integrations

```bash
# C++ Development
~/.config/sketchybar/helpers/cpp_project_switch.sh list

# SSH Connections
cat ~/.ssh/config | grep "^Host "

# Google Tools
# Open menu: Apple Menu > Google C++
```

### Test Widgets

1. **C++ Build Status**: Should show current project status
2. **SSH Connections**: Should show active connections
3. **Bazel Status**: Should show Bazel server/build status

## Common Work Environment Issues

### Issue: Corporate Firewall Blocks GitHub

**Solution:**
- Use git clone with SSH instead of HTTPS
- Or download ZIP and extract manually
- Or use corporate Git mirror if available

### Issue: Security Software Blocks Scripts

**Solution:**
- Whitelist `~/.config/sketchybar/` in security software
- May need IT approval for script execution

### Issue: VPN Required for Internal Tools

**Solution:**
- Ensure VPN is connected before using Google tools
- Configure VPN auto-connect if possible
- Use menu items that check VPN status

### Issue: Network Restrictions

**Solution:**
- Use git clone method (no Homebrew needed)
- Download dependencies manually
- Configure proxy settings

## Security Considerations

### For Work Computers

1. **No Root Access Required**: All installation in user space
2. **Minimal Permissions**: Only what's necessary
3. **Audit Trail**: All changes logged
4. **Easy Rollback**: Can be completely removed

### What Barista Does

- ✅ Installs to `~/.config/sketchybar` (user space)
- ✅ Creates launch agents in `~/Library/LaunchAgents` (user space)
- ✅ No system file modifications
- ✅ No network services (local only)
- ✅ All scripts are readable/auditable

### What Barista Doesn't Do

- ❌ No root/sudo access
- ❌ No system file changes
- ❌ No network servers
- ❌ No data collection
- ❌ No external connections (except GitHub for updates)

## Rollback Procedure

### Quick Disable

```bash
# Stop SketchyBar
brew services stop sketchybar
# Or: launchctl bootout gui/$(id -u)/homebrew.mxcl.sketchybar

# Remove launch agent
launchctl bootout gui/$(id -u)/dev.barista.control
rm ~/Library/LaunchAgents/dev.barista.control.plist
```

### Full Removal

```bash
# Uninstall (Homebrew)
brew uninstall barista

# Or remove (Git Clone)
rm -rf ~/.config/sketchybar

# Remove launch agents
rm ~/Library/LaunchAgents/dev.barista.control.plist

# Restore backups if needed
cp -r ~/.config/sketchybar.backup.* ~/.config/sketchybar
```

## Best Practices for Work

1. **Start with Minimal Profile**: Test basic functionality first
2. **Add Integrations Gradually**: One at a time, test each
3. **Keep Backups**: Regular backups of state.json
4. **Document Customizations**: Note what you changed
5. **Test Updates**: Test update process before relying on it
6. **Use Git Clone Method**: More control, easier to customize
7. **Version Control Your Config**: Consider git for state.json

## Troubleshooting

### Logs Location

```bash
# SketchyBar logs
tail -f ~/Library/Logs/sketchybar/sketchybar.log

# Launch agent logs
tail -f /tmp/barista.control.out.log
tail -f /tmp/barista.control.err.log
```

### Common Commands

```bash
# Check status
brew services list

# Reload configuration
sketchybar --reload

# Rebuild components
cd ~/.config/sketchybar
cmake -B build -S . && cmake --build build

# Check permissions
~/.config/sketchybar/helpers/setup_permissions.sh
```

## Updating on Work Machines

- Preferred: `BARISTA_SKIP_RESTART=1 ~/.config/sketchybar/bin/barista-update` (let corporate tooling restart services)
- If Homebrew is allowed: `brew upgrade barista && ~/.config/sketchybar/helpers/post_update.sh`
- If restarts are permitted locally: `~/.config/sketchybar/launch_agents/barista-launch.sh restart`

## Next Steps

1. ✅ Complete pre-flight checklist
2. ✅ Choose installation method
3. ✅ Install Barista
4. ✅ Configure work profile
5. ✅ Test basic functionality
6. ✅ Add C++ development integration
7. ✅ Configure SSH connections
8. ✅ Enable Google C++ tools
9. ✅ Customize for your workflow
10. ✅ Document your setup

## Support

- **Documentation**: See `docs/` directory
- **Quick Reference**: `QUICK_REFERENCE.md`
- **Workflows Guide**: `docs/GOOGLE_CPP_WORKFLOWS.md`
- **GitHub Issues**: For bugs or questions

---

**Ready?** Start with the pre-flight checklist and work through each step methodically!
