# Integration Status

## ✅ Completed

### 1. New Unified Config Window Built
- ✅ Created modular architecture with 11 tab view controllers
- ✅ Organized code into `gui/src/core/` and `gui/src/tabs/`
- ✅ Successfully builds: `build/bin/config_menu`
- ✅ Includes all features: Themes, Shortcuts, Launch Agents, Debug, Performance tabs

### 2. Scripts Updated
- ✅ `plugins/apple_menu.sh` - Now launches new `config_menu` (with fallback)
- ✅ `bin/open_control_panel.sh` - Updated to use new unified config window
- ✅ Scripts check for source build first, then installed binary

## ⚠️ Partially Complete

### 3. Config Window Integration
- ✅ Scripts updated to launch new window
- ⚠️ **You need to rebuild and test**: The new window should now launch when you shift-click
- ⚠️ **Installation**: Binary needs to be copied to `~/.config/sketchybar/gui/bin/config_menu` for production use

## ❌ Not Yet Fixed

### 4. Submenu Race Conditions
The submenu hover system has known race conditions that cause flickering and unreliable behavior:

**Issues:**
- Multiple `fork()` processes can be created for the same submenu
- No PID tracking or cancellation mechanism
- Fixed 0.25s delay may be too short for fast mouse movements
- No file locking to prevent race conditions
- Scheduled closes can fire after new opens

**Files to fix:**
- `helpers/submenu_hover.c` - Needs PID tracking, file locking, cancellation
- `helpers/popup_guard.c` - May need improvements for better coordination

**Planned fixes:**
1. Add PID tracking to cancel pending closes
2. Add file locking to prevent race conditions
3. Make delay configurable via environment variable (already partially done)
4. Improve hover zone detection
5. Better state synchronization between submenu_hover and popup_guard

## How to Test the New Config Window

1. **Rebuild the GUI:**
   ```bash
   cd ~/Code/barista
   ./rebuild_gui.sh
   ```

2. **Test launch:**
   ```bash
   # Should launch the new unified config window
   ./plugins/apple_menu.sh --panel
   ```

3. **Or shift-click the control center icon** in SketchyBar

4. **Check logs:**
   ```bash
   tail -f /tmp/sketchybar_config_menu.log
   ```

5. **Install for production** (optional):
   ```bash
   cp build/bin/config_menu ~/.config/sketchybar/gui/bin/
   ```

## Next Steps

1. **Test the new config window** - Verify it launches and all tabs work
2. **Fix submenu race conditions** - Implement PID tracking and file locking
3. **Improve submenu UX** - Configurable delays, better hover zones
4. **Install binary** - Copy to production location if needed

## Quick Commands

```bash
# Rebuild GUI
./rebuild_gui.sh

# Rebuild everything
./rebuild.sh

# Launch config window manually
./build/bin/config_menu

# Check if it's working
ps aux | grep config_menu
```

