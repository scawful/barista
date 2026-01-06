# SketchyBar Debugging Analysis Report

**Date**: November 17, 2025
**Status**: Comprehensive analysis of all current known issues

---

## Executive Summary

This document provides a detailed analysis of all current issues identified in the SketchyBar project. There are 4 major categories of issues spanning icon rendering, app detection, UI interaction, and control panel functionality.

---

## Issue 1: Icons Display Problem (Critical)

### Problem Description
Multiple critical icons fail to render due to empty string definitions in the icon library.

### Root Cause Analysis

The issue stems from a mismatch between two icon libraries:

#### File: `/Users/scawful/src/sketchybar/modules/icons.lua`

**Lines with Empty Icon Definitions:**
- Line 9: `apple = ""` (should display Apple logo)
- Line 10: `apple_alt = ""` (alternative Apple logo)
- Line 11: `settings = ""` (Settings icon)
- Line 12: `gear = ""` (Gear icon - duplicate of settings)
- Line 13: `power = ""` (Power button icon)
- Line 20: `bell = ""` (Notification bell)
- Line 22: `calendar = ""` (Calendar icon)
- Line 23: `clock = ""` (Clock icon)
- Line 24: `battery = ""` (Battery icon)
- Line 35: `code = ""` (Code editor icon)

These are defined in the `icons.categories.system` table and other categories, but contain empty strings instead of Nerd Font glyphs.

#### File: `/Users/scawful/src/sketchybar/modules/icon_manager.lua`

**Status**: Has correct icon definitions with fallback support (lines 19-167)

This file defines icons with proper Nerd Font characters:
```lua
apple = {
  glyphs = {
    {char = "", font = "Hack Nerd Font", desc = "Apple logo (Nerd Font)"},
    {char = "", font = "SF Symbols", desc = "Apple logo (SF Symbols)"},
  }
},
```

However, the `icon_manager.lua` file only covers ~20 icons directly and relies on importing from `icons.lua` via the `import_from_module()` function (lines 274-289) for the rest. When it imports from `icons.lua`, it imports the empty strings.

### Impact Areas

**Primary Impact - main.lua (Line 326)**:
```lua
icon = icon_for("apple", ""),
```
The Apple menu icon displays as empty because `icon_for()` function returns an empty string for the "apple" icon.

**Function Chain (main.lua, lines 142-163)**:
```lua
local function icon_for(name, fallback)
  -- First try state icons
  local state_icon = state_module.get_icon(state, name)
  if state_icon then
    local icon = safe_icon(state_icon)
    if icon then return icon end
  end

  -- Then try icon_manager (with multi-font support)
  local icon_char = icon_manager.get_char(name)
  if icon_char and icon_char ~= "" then
    return safe_icon(icon_char) or fallback
  end

  -- Fallback to old icon library for compatibility
  local lib_icon = icons_module.find(name)
  if lib_icon then
    return safe_icon(lib_icon) or fallback
  end

  return safe_icon(fallback) or fallback
end
```

When the lookup reaches `icons_module.find(name)`, it returns the empty string from `icons.lua` line 9, which passes the `safe_icon()` validation (empty string is valid UTF-8), so the empty string gets used instead of the fallback.

**Secondary Impact - Calendar Widget (main.lua, line 617)**:
```lua
icon = "",
```
Calendar icon in popup items shows as empty.

### Affected Icons Summary

| Icon Name | File Location | Expected | Current | Used In |
|-----------|---------------|----------|---------|---------|
| apple | icons.lua:9 | `` | `""` | Apple menu button |
| apple_alt | icons.lua:10 | `` | `""` | Not currently used |
| settings | icons.lua:11 | `` | `""` | Control panels |
| gear | icons.lua:12 | `` | `""` | Settings (duplicate) |
| power | icons.lua:13 | `` | `""` | Power menu |
| bell | icons.lua:20 | `` | `""` | Notifications |
| calendar | icons.lua:22 | `` | `""` | Clock popup (line 617) |
| clock | icons.lua:23 | `` | `""` | Time display |
| battery | icons.lua:24 | `` | `""` | Battery widget |
| code | icons.lua:35 | `` | `""` | Development menu |

### Proposed Solution

**Option A: Fix icons.lua (Recommended)**
Replace all empty strings with correct Nerd Font glyphs. This requires:
1. Identify correct Unicode codepoints for each icon
2. Update lines 9-13, 20, 22-24, 35 and others with proper glyphs
3. Ensure compatibility with "Hack Nerd Font" as primary font

**Option B: Fix icon_manager.lua**
Expand the icon_manager library to cover all icons and change the `safe_icon()` function in main.lua (line 134) to reject empty strings as valid icons.

**Option C: Fix icon_for() Function**
Modify the fallback chain in main.lua to provide better defaults when icon_manager returns empty strings.

**Recommended Implementation**: Option A + validate Option B coverage
- Fix all empty strings in `icons.lua` with proper Nerd Font characters
- Ensure `icon_manager.lua` has entries for frequently-used icons
- Update `safe_icon()` validation to treat empty strings as invalid (recommend)

---

## Issue 2: Front App Detection Issue (Moderate)

### Problem Description
The front app detection correctly identifies the frontmost application, but displays SketchyBar's own control panel binary (`config_menu_v2`) as the active app instead of filtering it out and showing the actual user application behind it.

### Root Cause Analysis

#### File: `/Users/scawful/src/sketchybar/plugins/front_app.sh`

**Current Behavior (lines 1-29)**:
```bash
#!/bin/sh

ICON_SCRIPT="$HOME/.config/sketchybar/scripts/app_icon.sh"
APP_NAME="$INFO"

if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

if [ "$SENDER" != "front_app_switched" ]; then
  APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

ICON="󰣆"
if [ -x "$ICON_SCRIPT" ]; then
  LOOKUP=$("$ICON_SCRIPT" "$APP_NAME")
  if [ -n "$LOOKUP" ]; then
    ICON="$LOOKUP"
  fi
fi

sketchybar --set "$NAME" icon="$ICON" label="$APP_NAME"
sketchybar --set front_app.menu.header label="App Controls · $APP_NAME" >/dev/null 2>&1 || true
```

**The Issue**:
When a user launches the config_menu_v2 control panel (which happens via apple_menu.sh), the macOS system reports it as the frontmost application. The script correctly detects it and displays it. However, users expect to see the application that was previously active BEHIND the control panel, not the control panel itself.

#### File: `/Users/scawful/src/sketchybar/plugins/apple_menu.sh` (lines 1-20)

```bash
PANEL_BIN="${GUI_DIR}/bin/config_menu_v2"

launch_panel() {
  if [ ! -x "$PANEL_BIN" ] && [ -d "$GUI_DIR" ]; then
    if ! make -C "$GUI_DIR" >"$BUILD_LOG" 2>&1; then
      osascript -e 'display alert "SketchyBar" message "Control panel build failed. See '"$BUILD_LOG"'"' >/dev/null 2>&1 || true
      return
    fi
  fi
  if [ -x "$PANEL_BIN" ]; then
    "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
  fi
}
```

The control panel is launched as a background process (`&`), but it becomes frontmost because it's a GUI application.

#### Related File: `/Users/scawful/src/sketchybar/plugins/halext_menu.sh`

Similar issue exists here (line 44-45):
```bash
"${CONFIG_DIR}/gui/bin/config_menu_v2" &
```

### Barista Binaries to Filter

The following binaries are part of SketchyBar's control system and should be filtered from app display:

1. **config_menu** - Original control panel
2. **config_menu_v2** - Current control panel (Primary)
3. **help_center** - Help documentation viewer
4. **icon_browser** - Icon selection utility

### Impact

When these tools are launched, the user sees:
- "config_menu_v2" displayed in the bar instead of actual app name
- Misleading status of what application they're currently working in
- Confusing behavior when switching between apps and control panels

### Proposed Solution

**Implement App Filtering in front_app.sh**:

```bash
#!/bin/sh

ICON_SCRIPT="$HOME/.config/sketchybar/scripts/app_icon.sh"
APP_NAME="$INFO"
BARISTA_APPS=("config_menu_v2" "config_menu" "help_center" "icon_browser")

if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

if [ "$SENDER" != "front_app_switched" ]; then
  APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
fi

# Filter out barista's own applications
for barista_app in "${BARISTA_APPS[@]}"; do
  if [ "$APP_NAME" = "$barista_app" ]; then
    # Try to get the previous non-barista app from system state
    # For now, show a placeholder or cached previous app
    APP_NAME="SketchyBar"
    break
  fi
done

if [ -z "$APP_NAME" ]; then
  exit 0
fi

ICON="󰣆"
if [ -x "$ICON_SCRIPT" ]; then
  LOOKUP=$("$ICON_SCRIPT" "$APP_NAME")
  if [ -n "$LOOKUP" ]; then
    ICON="$LOOKUP"
  fi
fi

sketchybar --set "$NAME" icon="$ICON" label="$APP_NAME"
sketchybar --set front_app.menu.header label="App Controls · $APP_NAME" >/dev/null 2>&1 || true
```

**Alternative: Caching Previous App**

Implement a state file to store the previously active non-barista app:

```bash
PREV_APP_FILE="/tmp/sketchybar_prev_app"

# Store non-barista apps
if ! app_is_barista "$APP_NAME"; then
  echo "$APP_NAME" > "$PREV_APP_FILE"
else
  # Use cached app if current is barista
  if [ -f "$PREV_APP_FILE" ]; then
    APP_NAME=$(cat "$PREV_APP_FILE")
  else
    APP_NAME="SketchyBar"
  fi
fi
```

**Best Practice: Make Control Panel Non-Activating**

Modify the Objective-C code in `gui/config_menu_v2.m` to:
1. Launch with `LSUIElement=1` in Info.plist (makes it not appear in Dock)
2. Use `NSApplicationActivationPolicyAccessory` to prevent it from becoming key window
3. Return focus to previously active app after launch

---

## Issue 3: Submenu Hover Behavior (Investigation Required)

### Problem Description
Submenus in the Apple menu may have issues with nested submenu support and hover behavior transitions. Need to verify:
1. Hovering from one submenu to another works correctly
2. Parent menu stays open when moving pointer between submenus
3. Smooth transitions between nested levels

### Analysis of Current Implementation

#### File: `/Users/scawful/src/sketchybar/helpers/submenu_hover.c`

**Current Features Implemented**:

1. **State Management** (lines 27-62):
   - Tracks active submenu in `/tmp/sketchybar_submenu_active`
   - Tracks parent popup lock in `/tmp/sketchybar_parent_popup_lock`
   - Prevents race conditions with file-based state

2. **Mouse Entry Handler** (lines 134-142):
   ```c
   if (!sender || strcmp(sender, "mouse.entered") == 0) {
     close_other_submenus(name);
     record_active(name);
     record_parent_open();  // Lock parent popup from closing
     run_cmd("sketchybar --set %s popup.drawing=on background.drawing=on "
             "background.color=%s background.corner_radius=6 "
             "background.padding_left=4 background.padding_right=4",
             name, HOVER_BG);
     return 0;
   }
   ```
   - Opens submenu on hover
   - Closes other submenus immediately
   - Locks parent menu open

3. **Mouse Exit Handler** (lines 145-147):
   ```c
   if (strcmp(sender, "mouse.exited") == 0) {
     schedule_close(name);
     return 0;
   }
   ```
   - Uses delayed close (250ms default) to allow pointer movement

4. **Global Exit Handler** (lines 150-158):
   ```c
   if (strcmp(sender, "mouse.exited.global") == 0) {
     // Global exit: close everything
     clear_active();
     close_other_submenus(name);
     run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
             name, IDLE_BG);
     // Also close parent popup
     run_cmd("sketchybar --set %s popup.drawing=off", PARENT_POPUP);
     return 0;
   }
   ```
   - Closes all submenus when leaving popup area entirely

**Defined Submenus** (lines 12-23):
```c
static const char *SUBMENUS[] = {
  "menu.sketchybar.styles",
  "menu.sketchybar.tools",
  "menu.yabai.section",
  "menu.windows.section",
  "menu.rom.section",
  "menu.emacs.section",
  "menu.halext.section",
  "menu.apps.section",
  "menu.dev.section",
  "menu.help.section"
};
```

### Potential Issues to Test

1. **Fast Pointer Movement** (Critical)
   - Test hovering quickly between submenu items
   - Expected: Previous submenu closes, new one opens
   - Risk: Delay timing (250ms) might be too long or too short

2. **Nested Submenus** (Important)
   - Current implementation assumes flat submenu structure
   - Each submenu is treated independently
   - No explicit handling for sub-submenu hierarchies

3. **Edge Cases**:
   - Moving from submenu to parent menu item and back
   - Pointer leaving popup entirely while in transition
   - Rapid enter/exit cycles

### Recommended Testing Steps

1. **Build and Run**:
   ```bash
   cd /Users/scawful/src/sketchybar/helpers
   make submenu_hover
   ```

2. **Manual Testing**:
   - Open apple menu
   - Hover over "Styles" submenu → verify it opens
   - Move pointer to adjacent submenu → verify previous closes, new opens
   - Check for visual glitches or delays

3. **Timing Tests**:
   - Test with different `CLOSE_DELAY` values (100ms, 250ms, 500ms)
   - Verify no "flickering" when transitioning between submenus

4. **Integration Tests**:
   - Test with popup_guard or popup_hover scripts
   - Verify interaction with apple_menu.sh

### Proposed Improvements

**Add Per-Submenu Configuration**:
```c
struct SubmenuConfig {
  const char *name;
  double hover_delay;  // Delay before opening
  double close_delay;  // Delay before closing
  int has_children;    // Flag for nested submenus
};
```

**Improve Nested Submenu Support**:
```c
// Instead of hardcoded SUBMENUS array, use hierarchical structure
static struct SubmenuConfig SUBMENUS[] = {
  {"menu.sketchybar.styles", 0, 0.25, 0},
  {"menu.sketchybar.tools", 0, 0.25, 0},
  // ... etc
};
```

---

## Issue 4: Control Panel Implementation Gaps (Enhancement Required)

### Problem Description
The control panel (config_menu_v2) is functional but missing several key features for a complete configuration management interface.

### Current Status

#### File: `/Users/scawful/src/sketchybar/gui/config_menu_v2.m`

**Currently Implemented Features** (lines 1-150 analyzed):
- Configuration state management (ConfigurationManager class)
- State persistence via JSON
- Appearance settings tab (height, corner radius, blur, scale)
- SketchyBar reload functionality

**Build Status**:
File: `/Users/scawful/src/sketchybar/gui/Makefile` (lines 1-42)
```makefile
all: $(BIN_CONFIG) $(BIN_CONFIG_V2) $(BIN_ICONS) $(BIN_HELP)

$(BIN_CONFIG_V2): $(SRC_CONFIG_V2)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_CONFIG_V2) -o $(BIN_CONFIG_V2)

clean:
	rm -rf $(BIN_DIR)
```
- Currently builds successfully to `/Users/scawful/src/sketchybar/gui/bin/config_menu_v2`
- Binary timestamp: Nov 17 09:29 (recently built)
- No known build failures

### Missing Features

#### 1. Theme Switching Capability (High Priority)

**Current State**:
- Themes exist in `/Users/scawful/src/sketchybar/themes/` (mocha, caramel, white_coffee, etc.)
- No UI in control panel to switch themes
- Must be done via configuration files or scripts

**Required Implementation**:
```objc
@interface ThemesTabViewController : NSViewController
- (void)loadThemeList;
- (void)applyTheme:(NSString *)themeName;
- (void)displayThemePreview:(NSString *)themeName;
@end
```

**Integration Point**:
- Menu context has theme in `menu_context.theme` (main.lua line 355)
- Themes are modules that return color palettes
- Need to add theme selection to state.json

#### 2. Keyboard Shortcut Configuration (Medium Priority)

**Current State**:
- Shortcuts module exists at `/Users/scawful/src/sketchybar/modules/shortcuts.lua`
- shortcuts.lua is loaded in main.lua (line 20)
- No UI to configure keyboard shortcuts
- Shortcuts are hardcoded in scripts

**Required Implementation**:
```objc
@interface ShortcutsTabViewController : NSViewController
- (void)loadShortcutsList;
- (void)recordShortcut:(NSString *)action;
- (void)validateShortcut:(NSString *)shortcut;
@end
```

**Integration Point**:
- Store shortcuts in state.json under `keyboard.shortcuts`
- Load in shortcuts module for script binding
- Validate against system shortcuts

#### 3. Icon Management and Preview (Medium Priority)

**Current State**:
- Icon browser exists at `/Users/scawful/src/sketchybar/gui/bin/icon_browser`
- icon_manager.lua provides icon access (line 19 of main.lua)
- Icon library functions: `icons.search()`, `icons.get_all()` (modules/icons.lua lines 289-325)
- No integrated icon preview in main control panel

**Required Implementation**:
```objc
@interface IconManagerTabViewController : NSViewController
@property (strong) NSSearchField *searchField;
@property (strong) NSTableView *iconsTable;
- (void)searchIcons:(NSString *)query;
- (void)previewIcon:(NSString *)iconName;
- (void)copyIconToClipboard:(NSString *)glyph;
@end
```

**Integration Point**:
- Query icon system via Lua script execution
- Display icons in grid/table view
- Allow copy-to-clipboard for use in configuration

#### 4. Build Issues and Failures (Current Status: None Known)

**Recent Build Status** (from timestamps):
- Last successful build: Nov 17, 09:29 (config_menu_v2)
- No compilation errors reported
- Build process: uses `clang` with Cocoa frameworks

**Potential Future Issues to Prevent**:
1. **Framework Dependencies**: Cocoa, Foundation, UniformTypeIdentifiers
   - Ensure they're available in build environment
   - Add fallback implementations if needed

2. **Code Signing**:
   - GUI apps may require code signing for launchctl integration
   - Currently works with direct execution

3. **Sandbox Restrictions**:
   - If run under sandbox, state file access may fail
   - Path hardcoded to `~/.config/sketchybar/state.json`

### Proposed Implementation Roadmap

**Phase 1: Theme Switching (Immediate)**
1. Add ThemesTabViewController to config_menu_v2.m
2. Enumerate theme files in themes/ directory
3. Update state.json with current theme selection
4. Reload SketchyBar to apply theme

**Phase 2: Keyboard Shortcuts (Short-term)**
1. Add ShortcutsTabViewController
2. Create keyboard input recorder with modifiers
3. Validate against system shortcuts (using AXUIElement)
4. Store in state.json and reload

**Phase 3: Icon Management (Short-term)**
1. Add IconManagerTabViewController
2. Integrate with icon_manager.lua via script execution
3. Display in grid with search capability
4. Copy-to-clipboard for icon glyphs

**Phase 4: Additional Features (Long-term)**
1. Color picker for custom color schemes
2. Profile management (work/personal/minimal)
3. Plugin enable/disable toggles
4. Export/import configuration

---

## Testing and Validation Checklist

### Icon Display Testing
- [ ] Apple menu icon displays correctly (not empty)
- [ ] Settings icon displays in menus
- [ ] Battery, clock, calendar icons all render
- [ ] All common system icons display in icon_browser

### Front App Detection Testing
- [ ] Launching config_menu_v2 doesn't show panel name in bar
- [ ] Showing actual app behind control panel
- [ ] Previous app persists after closing panel
- [ ] Works with help_center and icon_browser

### Submenu Hover Testing
- [ ] Quick hover between submenus works smoothly
- [ ] No visual flicker or delays
- [ ] Parent menu stays open during transitions
- [ ] Global exit closes all submenus

### Control Panel Testing
- [ ] Appearance settings save and apply
- [ ] Theme switching works (when implemented)
- [ ] Shortcuts configuration works (when implemented)
- [ ] Icon management accessible (when implemented)
- [ ] No build errors with `make -C gui`

---

## File References Summary

### Critical Files
| File | Issue | Lines | Priority |
|------|-------|-------|----------|
| `/Users/scawful/src/sketchybar/modules/icons.lua` | Empty icon strings | 9-13, 20, 22-24, 35 | Critical |
| `/Users/scawful/src/sketchybar/plugins/front_app.sh` | App filtering | 1-29 | Moderate |
| `/Users/scawful/src/sketchybar/helpers/submenu_hover.c` | Hover behavior | 78-162 | Low-Moderate |
| `/Users/scawful/src/sketchybar/gui/config_menu_v2.m` | Missing features | 1-150+ | Medium |

### Supporting Files
| File | Purpose |
|------|---------|
| `/Users/scawful/src/sketchybar/main.lua` | Icon lookup logic, menu setup |
| `/Users/scawful/src/sketchybar/modules/icon_manager.lua` | Multi-font icon support |
| `/Users/scawful/src/sketchybar/plugins/apple_menu.sh` | Control panel launcher |
| `/Users/scawful/src/sketchybar/gui/Makefile` | Build configuration |

---

## Conclusion

The SketchyBar project has solid foundational architecture with modular design. The identified issues are:

1. **Icon Display (Critical)** - High impact, straightforward fix
2. **App Detection (Moderate)** - Moderate impact, requires app filtering
3. **Submenu Hover (Low-Moderate)** - Low impact, needs testing/validation
4. **Control Panel Features (Medium)** - Enhancement, improves user experience

Addressing Issue #1 (Icon Display) should be the immediate priority as it affects core visual functionality. Issue #2 (App Detection) should follow as it improves user experience and clarity. Issues #3 and #4 are refinements that would enhance the overall system but are not blockers.

---

## Additional Resources

### Build Commands
```bash
# Build specific component
make -C /Users/scawful/src/sketchybar/gui config_v2

# Build all GUI components
make -C /Users/scawful/src/sketchybar/gui all

# Clean build artifacts
make -C /Users/scawful/src/sketchybar/gui clean
```

### Debugging Commands
```bash
# Check SketchyBar logs
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.log

# Test front app detection
osascript -e 'tell application "System Events" to name of first process whose frontmost is true'

# Monitor submenu state
watch -n 0.1 cat /tmp/sketchybar_submenu_active

# Reload SketchyBar config
/opt/homebrew/opt/sketchybar/bin/sketchybar --reload
```

### Icon Tools
```bash
# View all available icons
lua -e 'local i=require("icons"); for _,v in ipairs(i.get_all()) do print(v.name, v.glyph) end'

# Search for specific icon
lua -e 'local i=require("icons"); local r=i.search("apple"); for _,v in ipairs(r) do print(v.name, v.glyph) end'
```
