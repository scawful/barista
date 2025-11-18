# SketchyBar Configuration Architecture Analysis

## Executive Summary

This is a sophisticated macOS status bar configuration built on SketchyBar with a Lua/C hybrid architecture. It demonstrates:
- **Multi-tier event system** connecting SketchyBar → Lua configuration → C binaries → Yabai window manager
- **Persistent state management** through JSON-based state.json with fallback mechanisms
- **Complex menu system** with nested submenus, hover highlighting, and popup guards
- **Space management** with custom icons and layout modes synchronized across multiple components

Key insight: The system uses **file-based synchronization** between components (temp files for menu locks, JSON for persistent state) rather than true IPC, which introduces potential race conditions under concurrent operations.

---

## 1. Event Flow Architecture

### 1.1 SketchyBar Event Sources
```
┌─────────────────────────────────────────────────────────────┐
│           SketchyBar Event Triggers                          │
├─────────────────────────────────────────────────────────────┤
│ Built-in Events:                                            │
│  • mouse.entered / mouse.exited / mouse.exited.global       │
│  • volume_change                                            │
│  • system_woke                                              │
│  • power_source_change                                      │
│  • front_app_switched                                       │
│  • display_changed / display_added / display_removed        │
│                                                              │
│ Yabai Integration Events:                                   │
│  • space_changed (via Yabai signal)                         │
│  • space_created (via Yabai signal)                         │
│  • space_destroyed (via Yabai signal)                       │
│  • display_changed (via Yabai signal)                       │
│                                                              │
│ Custom Events (created in main.lua):                        │
│  • space_change (line 279)                                  │
│  • space_mode_refresh (line 280)                            │
│  • whichkey_toggle (line 281)                               │
│  • yabai_status_refresh (line 493)                          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Event Subscription Pattern

**Main.lua Event Subscriptions:**
```lua
Line 289:   popup_manager subscribes to:
            space_change, display_changed, display_added, 
            display_removed, system_woke, front_app_switched

Line 357:   apple_menu subscribes to:
            mouse.entered, mouse.exited, mouse.exited.global

Line 459:   front_app subscribes to:
            front_app_switched

Line 460:   front_app subscribes to (via subscribe_popup_autoclose):
            mouse.entered, mouse.exited, mouse.exited.global

Line 494:   yabai_status subscribes to:
            yabai_status_refresh, system_woke, front_app_switched, space_change

Line 785:   volume subscribes to:
            volume_change

Line 793:   battery subscribes to:
            system_woke, power_source_change
```

### 1.3 Yabai Signal Setup (watch_spaces function, lines 201-216)

When Yabai is available, these signals are registered:
```bash
yabai -m signal --add event=space_changed 
  action='sketchybar --trigger space_change'
yabai -m signal --add event=space_created 
  action='CONFIG_DIR=... plugins/refresh_spaces.sh'
yabai -m signal --add event=space_destroyed 
  action='CONFIG_DIR=... plugins/refresh_spaces.sh'
yabai -m signal --add event=display_changed 
  action='CONFIG_DIR=... plugins/refresh_spaces.sh'
yabai -m signal --add event=display_added 
  action='CONFIG_DIR=... plugins/refresh_spaces.sh'
yabai -m signal --add event=display_removed 
  action='CONFIG_DIR=... plugins/refresh_spaces.sh'
```

### 1.4 Event Flow Chain: Space Creation Example

```
Yabai signal (space_created)
    ↓
refresh_spaces.sh (plugins/refresh_spaces.sh)
    ↓
spaces_setup.sh (plugins/spaces_setup.sh)
    ├─ Reads state.json for custom space_icons
    ├─ Queries yabai for all spaces
    ├─ Creates space items with subscribe: mouse.entered, mouse.exited, 
    │  space_change, space_mode_refresh
    └─ Adds space.sh as script for each space
    ↓
Subsequent space_change event
    ↓
space.sh (plugins/space.sh) for each space
    ├─ Runs on: space_change, space_mode_refresh, mouse.entered, mouse.exited
    ├─ Reads state.json for space_icons and space_modes
    ├─ Queries Yabai for active app on space
    ├─ Resolves icon priority: custom icon > app icon > empty
    └─ Updates UI via sketchybar commands
```

---

## 2. Icon System Architecture

### 2.1 Icon Resolution Chain (main.lua, lines 151-172)

```lua
function icon_for(name, fallback)
  -- Priority 1: State icons (persistent custom icons)
  local state_icon = state_module.get_icon(state, name)
  if state_icon then
    local icon = safe_icon(state_icon)
    if icon then return icon end
  end

  -- Priority 2: Icon Manager (multi-font support)
  local icon_char = icon_manager.get_char(name)
  if icon_char and icon_char ~= "" then
    return safe_icon(icon_char) or fallback
  end

  -- Priority 3: Legacy icon library (backward compatibility)
  local lib_icon = icons_module.find(name)
  if lib_icon then
    return safe_icon(lib_icon) or fallback
  end

  -- Fallback
  return safe_icon(fallback) or fallback
end
```

### 2.2 Icon Modules Breakdown

#### modules/icons.lua (Legacy)
- **Purpose:** Backward compatibility icon library
- **Structure:** Categorized icons (apps, development, system, etc.)
- **Access:** `icons.find(name)` searches all categories

#### modules/icon_manager.lua (Multi-Font)
- **Purpose:** Modern icon management with font fallback
- **Fonts:** Hack Nerd Font (priority 1), SF Pro, SF Symbols, Menlo
- **Features:**
  - `icon_manager.get(name, preferred_font)` returns {char, font, style}
  - `icon_manager.get_char(name)` returns just character (backward compat)
  - Bulk import from legacy icons module
  
#### modules/c_bridge.lua
- **Purpose:** Interface to C icon_manager binary
- **Functions:**
  - `c_bridge.icons.get(name, fallback)` - Fast C lookup
  - `c_bridge.icons.set(item, icon_name, fallback)` - Async set
  - `c_bridge.icons.search(query)` - Search icons
  - `c_bridge.icons.list_category(category)` - Get category icons

### 2.3 Space-Specific Icons

Space icons are stored in state.json at `space_icons.<space_number>`:

```json
{
  "space_icons": {
    "1": "󰀶",  // Finder
    "2": "",    // Safari
    "3": "󰈙",  // Editor
    "4": "󰍳"   // Terminal
  }
}
```

**Resolution in space.sh (plugins/space.sh, lines 138-165):**
```bash
# Priority order:
# 1. Custom icon from state.json
DEFAULT_ICON=$(get_default_icon)  # Python reads state.json

# 2. Active app icon
APP_ICON=$(resolve_app_icon)      # Uses app_icon.sh script

# 3. Default state indicators
if is_selected "$SELECTED"; then
  ICON_VALUE="•"   # Dot for active
else
  ICON_VALUE="○"   # Circle for inactive
fi
```

### 2.4 Icon Display Update Paths

**Path A: Direct state change**
```
GUI (config_menu_v2.m) sets space_icons.N
    ↓
ConfigurationManager writes state.json
    ↓
GUI calls sketchybar --reload or set_space_mode.sh
    ↓
space.sh reads new state and updates icon
```

**Path B: Space refresh**
```
Yabai space_created signal
    ↓
refresh_spaces.sh → spaces_setup.sh
    ↓
spaces_setup.sh reads state.json, creates/updates space items
    ↓
space.sh attached to each space item
```

---

## 3. Space Management System

### 3.1 Space Lifecycle

#### Creation
1. **Yabai creates space** via user action or yabai command
2. **Yabai signal triggers** `yabai -m signal event=space_created`
3. **refresh_spaces.sh** executed (called from Yabai signal)
4. **spaces_setup.sh** runs:
   - Removes all existing space.* items (line 61-62)
   - Queries `yabai -m query --spaces` (line 47)
   - Reads custom space_icons from state.json (Python, lines 11-29)
   - Creates space items (line 94-110)
   - Attaches space.sh script to each space
   - Subscribes to events: mouse.entered, mouse.exited, space_change, space_mode_refresh

#### Update
1. **space.sh script** attached to each space item
2. **Triggers on:** space_change, space_mode_refresh, mouse.entered, mouse.exited
3. **Operations:**
   - Reads space_icons and space_modes from state.json
   - Queries active app and resolves icon
   - Ensures desired layout mode matches Yabai state (lines 113-135)

#### Deletion
1. **Yabai deletes space**
2. **Yabai signal triggers** `yabai -m signal event=space_destroyed`
3. **refresh_spaces.sh** → **spaces_setup.sh** runs
4. **Removed space items** not recreated

### 3.2 Space Mode System

**Storage:** state.json at `space_modes.<space_number>`

**Modes:**
- "float" (default) - Not stored, presence of key indicates tiling
- "bsp" - Binary space partitioning
- "stack" - Stacked tiling

**Update flow:**
```
GUI (config_menu_v2.m applySettings) or set_space_mode.sh
    ↓
Update state.json via Python (set_space_mode.sh, lines 42-63)
    ├─ If mode == "float": remove key from space_modes
    └─ Else: set space_modes[str(space)] = mode
    ↓
apply_layout() calls: yabai -m space <N> --layout <mode>
    ↓
Trigger space_mode_refresh event
    ↓
space.sh runs ensure_space_layout (lines 113-135)
    ├─ Compares desired mode (from state.json)
    └─ With current Yabai mode (via yabai -m query --spaces --space)
    ↓
If mismatch: apply_layout() again
```

### 3.3 Critical Issue: Race Condition in Space Setup

**File: spaces_setup.sh, lines 46-52**

```bash
if DATA=$(yabai -m query --spaces 2>/dev/null); then
  while IFS= read -r line; do
    SPACE_LINES+=("$line")
  done < <(printf '%s\n' "$DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
fi
```

**Issue:** If spaces_setup.sh runs twice concurrently:
1. Both read yabai query
2. Both strip existing items with `/space\..*./` regex
3. First one writes space items
4. Second one overwrites with potentially stale data
5. Custom icons from state.json might be lost if read order changes

---

## 4. Front App System

### 4.1 Front App Widget Setup (main.lua, lines 439-465)

```lua
sbar.add("item", "front_app", {
  position = "left",
  icon = { drawing = true },
  label = { drawing = true },
  script = PLUGIN_DIR .. "/front_app.sh",
  click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
  -- ... popup configuration
})

sbar.exec("sketchybar --subscribe front_app front_app_switched")
subscribe_popup_autoclose("front_app")  -- mouse.entered, mouse.exited, mouse.exited.global
attach_hover("front_app")               -- hover highlighting
```

### 4.2 Front App Event Flow

**Event Trigger:** `front_app_switched` (built-in SketchyBar event)

**Script:** plugins/front_app.sh (lines 1-37)

```bash
# If sender is mouse.exited.global, close popup
if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# Get front app name (if not from front_app_switched event)
if [ "$SENDER" != "front_app_switched" ]; then
  APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
fi

# Filter out SketchyBar's own apps
if echo "$APP_NAME" | grep -qE "^($BARISTA_APPS)$"; then
  exit 0  # Don't update if our own app
fi

# Get app icon via app_icon.sh script
LOOKUP=$("$ICON_SCRIPT" "$APP_NAME")
if [ -n "$LOOKUP" ]; then
  ICON="$LOOKUP"
fi

# Update widget
sketchybar --set "$NAME" icon="$ICON" label="$APP_NAME"
```

### 4.3 Control Center Application Sections

Front-app window controls are now embedded inside the `control_center` popup:
- **Application Controls:** show/hide/quit/force quit via `front_app_action`.
- **Window Actions:** Float, Sticky, Fullscreen, Center, Restart skhd, etc.
- **Spaces Management:** Move windows between displays/spaces, send to slots 1‑5.
- **Space Layout:** Toggle BSP/Stack/Float through `set_space_mode.sh`.

---

## 5. Menu System Architecture

### 5.1 Menu Rendering Pipeline

**Entry Point:** main.lua, lines 427-464

```lua
menu_module.render_control_center(menu_context)      -- Unified Control Center
```

**Menu Context:** Large table (lines 361-417) containing:
- sbar, settings, theme references
- Script paths
- Helper functions: shell_exec, call_script, attach_hover
- Integration modules: yaze, emacs, halext

### 5.2 Menu Module Architecture (modules/menu.lua)

**Key Functions:**

1. **load_menu_section(ctx, name)** - Loads JSON menu definition
2. **create_renderer(ctx)** - Returns renderer with closures
3. **render_menu_items(popup, entries)** - Recursive submenu rendering

**Menu Item Types:**
```lua
{
  type = "header",    -- Non-clickable header
  type = "separator", -- Visual separator
  type = "submenu",   -- Has .items array
  -- default: clickable menu item
}
```

### 5.3 Menu Item Structure

```lua
{
  name = "menu.item.id",
  icon = "󰍛",
  label = "Item Label",
  shortcut = "⌘K",          -- Optional keyboard shortcut
  action = "command to run",
  type = "submenu",          -- Optional
  items = { ... }            -- For submenus
}
```

### 5.4 Submenu Hover Coordination

**Files involved:**
- modules/menu.lua: Renders submenus
- helpers/submenu_hover.c: Handles hover state
- helpers/popup_guard.c: Prevents parent closing

**Flow:**

```
User hovers on submenu parent
    ↓
submenu_hover.c (HOVER_SCRIPT) on mouse.entered
    ├─ Closes other open submenus
    ├─ Records active submenu in /tmp/sketchybar_submenu_active
    ├─ Writes parent lock to /tmp/sketchybar_parent_popup_lock
    ├─ Opens submenu popup with drawing=on
    └─ Sets background color to HOVER_BG (0x80cba6f7)
    ↓
User moves mouse out of submenu
    ↓
submenu_hover.c on mouse.exited
    ├─ Forks background process
    ├─ Waits CLOSE_DELAY (0.25s by default, env: SUBMENU_CLOSE_DELAY)
    ├─ Checks if still hovering (reads /tmp/sketchybar_submenu_active)
    └─ If not, closes submenu popup
    ↓
Parent popup's mouse.exited event
    ↓
popup_guard.c (script on apple_menu)
    ├─ Checks /tmp/sketchybar_parent_popup_lock
    ├─ If submenu open: do nothing (let submenu control closing)
    └─ If submenu closed: close parent popup
```

### 5.5 Menu Action Wrapper (menu_action.sh)

**Location:** plugins/menu_action.sh

```bash
ITEM_NAME="${1:-}"
POPUP_NAME="${2:-}"
COMMAND="${MENU_ACTION_CMD:-}"

# Highlight item on click
sketchybar --set "$ITEM_NAME" background.drawing=on background.color="$HILITE_COLOR"

# Run action asynchronously (nohup)
nohup bash -lc "$COMMAND" >/tmp/sketchybar_menu_action.log 2>&1 &

# Close popup
sketchybar --set "$POPUP_NAME" popup.drawing=off

# Wait for visual feedback
sleep "$IDLE_DELAY"

# Remove highlight
sketchybar --set "$ITEM_NAME" background.drawing=off
```

---

## 6. Control Panel (GUI) Architecture

### 6.1 File: gui/config_menu_v2.m

**Main Components:**

1. **ConfigurationManager** (lines 6-121)
   - Singleton managing state.json I/O
   - Load/save with error recovery
   - KeyPath access (dot-notation): "appearance.bar_height"

2. **Tab View Controllers:**
   - AppearanceTabViewController (lines 125-391)
   - SpacesTabViewController (lines 594-807)
   - IconsTabViewController (lines 811-1100)
   - ToggleTabViewController, ThemesTabViewController, etc.

### 6.2 Spaces Tab Implementation

**State Properties:**
- currentSpace: NSInteger (1-based index)
- spaceSelector: NSComboBox (space selection)
- iconField: NSTextField (custom icon input)
- iconPreview: NSTextField (live preview)
- modeSelector: NSSegmentedControl (float/bsp/stack)

**Key Methods:**

```objc
- (void)spaceChanged:(id)sender
  // Update UI when space selection changes
  // Calls loadSpaceSettings

- (void)loadSpaceSettings
  // Read from state.json
  // Load space_icons.<space> and space_modes.<space>
  // Update UI fields

- (void)applySettings:(id)sender
  // Save to state.json
  // Call set_space_mode.sh if mode changed
  // Trigger sketchybar --reload
```

### 6.3 Data Flow: GUI → State → Bar

```
User selects space in GUI
    ↓
spaceChanged() → loadSpaceSettings()
    ↓
ConfigurationManager reads space_icons.<N>, space_modes.<N>
    ↓
UI shows current values
    ↓
User modifies icon or mode
    ↓
applySettings() triggered
    ↓
ConfigurationManager.setValue() writes state.json
    ↓
If mode changed: set_space_mode.sh executed
    ├─ Updates space_modes.<N> in state.json
    ├─ Applies layout via yabai -m space <N> --layout <mode>
    └─ Triggers space_mode_refresh event
    ↓
sketchybar --reload called
    ↓
main.lua re-evaluates with new state
    ├─ Icon manager may use new icon_manager settings
    └─ space.sh reads new space_icons and space_modes
    ↓
Bar updates with new icons/modes
```

---

## 7. C Components and Bridge System

### 7.1 C Bridge Module (modules/c_bridge.lua)

**Purpose:** Lightweight wrapper for C binaries in ~/.config/sketchybar/bin/

**Design Pattern:**
```lua
function c_bridge.icons.get(name, fallback)
  local result = exec_c("icon_manager", "get", name, fallback or "")
  if result then
    return result:gsub("%s+$", "")  -- Trim whitespace
  end
  return fallback or ""
end
```

**Binaries Interfaced:**
- icon_manager
- state_manager
- widget_manager
- menu_renderer

### 7.2 Component Switcher (modules/component_switcher.lua)

**Purpose:** Runtime selection between C and Lua implementations with performance tracking

**Modes:**
- "auto" - Use C if available, fallback to Lua
- "c" - Force C (error if unavailable)
- "lua" - Force Lua
- "hybrid" - Each component chooses independently

**Features:**
- Performance statistics tracking
- Auto-fallback on C failure
- Configurable via component_settings.json
- Health checks and reporting

### 7.3 Key C Helpers

#### popup_hover.c
- **Purpose:** Handle hover highlighting for menu items
- **Events:** mouse.entered, mouse.exited
- **State:** Records parent popup in /tmp/sketchybar_popup_state/active_parent
- **Logic:**
  ```c
  if mouse.entered:
    Set background.drawing=on, background.color=HIGHLIGHT
    Record SUBMENU_PARENT env var to state file
  if mouse.exited:
    Set background.drawing=off, background.color=IDLE
  ```

#### submenu_hover.c (92 lines)
- **Purpose:** Manage submenu opening/closing with timing
- **Lock files:**
  - /tmp/sketchybar_submenu_active - Current active submenu
  - /tmp/sketchybar_parent_popup_lock - Lock preventing parent close
- **Close delay:** 0.25s (configurable via SUBMENU_CLOSE_DELAY)
- **Key logic:**
  ```c
  on mouse.entered:
    Close other submenus (batch command)
    Record this submenu as active
    Write parent lock
    Show popup with background

  on mouse.exited:
    Fork background process
    Wait CLOSE_DELAY
    Check if still active (read from file)
    If not active: close popup
  
  on mouse.exited.global:
    Clear all locks
    Close all submenus
    Close parent popup
  ```

#### popup_guard.c (40 lines)
- **Purpose:** Prevent main popup from closing when submenus are open
- **Implementation:**
  ```c
  if mouse.exited or mouse.exited.global:
    if submenu lock exists:
      do nothing (let submenu control)
    else:
      close parent popup
  ```

---

## 8. Data Flow Synchronization Points

### 8.1 State Persistence

**File:** ~/.config/sketchybar/state.json

**Read sources:**
- main.lua initialization (line 69)
- modules/state.lua (load function)
- space.sh (via Python inline script)
- plugins/spaces_setup.sh (via Python inline script)
- config_menu_v2.m (ConfigurationManager.loadState)

**Write sources:**
- modules/state.lua (save function)
- set_space_mode.sh (via Python inline script)
- config_menu_v2.m (ConfigurationManager.setValue)
- space.sh indirectly (triggers refreshes)

**Potential race condition:** Multiple concurrent writes to state.json
- Python json.dump is atomic on most filesystems
- But ordered reads of space_icons/space_modes could race

### 8.2 Temporary State Files (C Helpers)

**popup_hover.c:**
- Writes: /tmp/sketchybar_popup_state/active_parent
- Purpose: Track parent popup for submenu coordination
- Lifetime: Duration of hover

**submenu_hover.c:**
- Writes: /tmp/sketchybar_submenu_active
- Writes: /tmp/sketchybar_parent_popup_lock
- Purpose: Prevent parent close while submenu open
- Lifetime: Duration of submenu hover + CLOSE_DELAY

**popup_guard.c:**
- Reads: /tmp/sketchybar_parent_popup_lock
- Purpose: Guard parent closing
- Lifetime: Checked on parent mouse.exited

**Race condition:** If CLOSE_DELAY elapses while mouse is still in submenu:
1. Background process in submenu_hover unlinks lock file
2. Parent's mouse.exited fires
3. popup_guard reads missing lock file
4. Parent popup closes prematurely

---

## 9. Identified Issues and Race Conditions

### 9.1 CRITICAL: Submenu Close Timing Bug

**File:** helpers/submenu_hover.c, lines 96-114

```c
static void schedule_close(const char *name) {
  pid_t pid = fork();
  if (pid != 0) return;  // Parent returns immediately

  usleep((useconds_t)(CLOSE_DELAY * 1000000.0));  // Default 0.25s

  char current[256];
  if (!read_active(current, sizeof(current)) || strcmp(current, name) != 0) {
    // Close if inactive
    run_cmd("sketchybar --set %s popup.drawing=off ...", name);
  }
  _exit(0);
}
```

**Issue:** 
- If user hovers back before CLOSE_DELAY expires, submenu stays open
- BUT if they hover back at exactly CLOSE_DELAY + epsilon, both processes try to close
- Lock file deleted by background process before parent popup's mouse.exited fires
- Parent popup closes even though submenu might have been re-entered

**Scenario:**
```
T=0.0:  User enters submenu A
T=0.0:  Background close scheduled for T=0.25s
T=0.15: User moves mouse out briefly
T=0.2:  User moves mouse back in (re-enters submenu A)
T=0.25: Background process checks, submenu A is still active
        But another submenu B might now be active
        Race between closing A and B
```

### 9.2 Space Icon State Coherence

**File:** plugins/spaces_setup.sh, lines 11-42

```bash
CUSTOM_ICON_DATA=$(python3 - "$STATE_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}
# ... extract space_icons ...
```

**Issue:** 
- spaces_setup.sh reads state.json once at start
- If state.json is modified while spaces_setup.sh runs:
  - Old icons used for some spaces
  - New icons used for others
  - GUI shows different state than bar

### 9.3 Space Mode Application Timing

**File:** plugins/set_space_mode.sh, lines 77-80

```bash
update_state       # Updates state.json
apply_layout       # Calls yabai -m space <N> --layout <mode>
sketchybar --trigger space_mode_refresh
sketchybar --trigger yabai_status_refresh
```

**Issue:**
- state.json updated (line 77)
- Yabai command sent (line 78)
- If Yabai slow to respond, space.sh might read old state before Yabai completes
- Result: UI shows wrong mode icon

### 9.4 Component Switcher Auto-Fallback

**File:** modules/component_switcher.lua, lines 260-278

```lua
function component_switcher.execute(component, c_func, lua_func, ...)
  local impl = get_implementation(component)

  if impl == "c" then
    local ok, result = pcall(exec_c, component, ...)
    if ok then
      return result
    else
      if settings.auto_fallback then
        log(component, "C implementation failed, falling back to Lua: " .. tostring(result))
        return exec_lua(component, lua_func, ...)
      else
        error(...)
      end
    end
```

**Issue:**
- If C binary crashes or times out, fallback silently occurs
- Performance statistics might be misleading (fast failure != fast implementation)
- No notification to user that fallback happened

### 9.5 Icon Resolution UTF-8 Validation

**File:** main.lua, lines 138-149

```lua
local function safe_icon(value)
  if type(value) ~= "string" then
    return nil
  end
  local ok = pcall(function()
    utf8.len(value)
  end)
  if ok then
    return value
  end
  return nil
end
```

**Issue:**
- Icons from state.json are validated via UTF-8 length check
- But config_menu_v2.m doesn't validate before saving
- Corrupted UTF-8 in state.json from GUI input → icon silently drops
- No user feedback

### 9.6 Popup Dismissal Race with Space Change

**Main.lua, lines 284-289:**

```lua
sbar.add("item", "popup_manager", {
  position = "left",
  drawing = false,
  script = POPUP_MANAGER_SCRIPT,
})
sbar.exec("sketchybar --subscribe popup_manager space_change display_changed ...")
```

**Issue:**
- popup_manager dismisses popups on space_change
- But space items have `subscribe ... space_change` (spaces_setup.sh line 111)
- Both fire simultaneously
- Order of execution undefined: popup_manager might close before space.sh updates icons
- Or space.sh updates icons in old space before popup_manager closes

---

## 10. Information Flows and Dependencies

### 10.1 Widget Update Chain

```
SketchyBar Event → Script → State.json → UI Update
  ↓                ↓        ↓
volume_change   volume.sh  widget_colors
  ↓                ↓        ↓
                   widget update

front_app_switched → front_app.sh → icon resolution → label/icon update
  ↓                                 ↓
                                    app_icon.sh script

space_change → space.sh → state.json → icon selection → display update
  ↓            ↓         ↓
              yabai query app determination
```

### 10.2 Configuration Update Chain

```
GUI user action → ConfigurationManager.setValue() → state.json
  ↓                                                  ↓
                                                    sketchybar --reload or
                                                    specific trigger
  ↓                                                  ↓
                                                    main.lua re-evaluates
  ↓                                                  ↓
                                                    Lua state changes
  ↓                                                  ↓
                                                    Bar subscribes to events
  ↓                                                  ↓
                                                    Scripts read updated state.json
  ↓                                                  ↓
                                                    UI reflects changes
```

### 10.3 Space Lifecycle Configuration

```
Yabai signal (space_* events)
  ↓
refresh_spaces.sh
  ├─ Read state.json (space_icons, space_modes)
  ├─ Query Yabai (current spaces)
  ├─ Create space items
  └─ Attach space.sh scripts
  ↓
space.sh (on space_change, space_mode_refresh, hover)
  ├─ Read state.json (space_icons, space_modes)
  ├─ Query Yabai (active app)
  ├─ Ensure layout matches desired mode
  └─ Update icon display
  ↓
space_mode_refresh event
  ├─ Triggers on: set_space_mode.sh completion
  ├─ space.sh runs ensure_space_layout
  └─ Verifies Yabai and UI are in sync
```

---

## 11. Architecture Strengths

1. **Modular Design:** Separation of concerns (icons, state, widgets, menus)
2. **Multi-Component:** Hybrid C/Lua allows performance where needed
3. **Persistent State:** JSON-based configuration survives restarts
4. **Event-Driven:** Responsive to system changes (Yabai, front app, etc.)
5. **Fallback Mechanisms:** Component switcher handles missing C binaries
6. **Theme System:** Centralized color and appearance management
7. **Integration Hooks:** Yaze, Emacs, WhichKey modules can be plugged in

---

## 12. Architecture Weaknesses

1. **File-Based Synchronization:** Uses /tmp files instead of true IPC
   - Prone to race conditions
   - No guaranteed atomicity across processes
   
2. **No Transaction System:** State changes not atomic
   - Icon update might succeed while mode update fails
   
3. **Silent Failures:** Bad UTF-8 in state drops silently
   - No logging or user notification
   
4. **Timing Dependencies:** Submenu hover uses fixed 0.25s delay
   - Might be too short on slow systems
   - Might be too long on fast systems
   
5. **Concurrent Updates:** Multiple scripts might modify state.json simultaneously
   - Last-write-wins semantics could lose data
   
6. **Lack of Validation:** GUI doesn't validate input before saving
   - Could corrupt state.json
   
7. **Order Dependencies:** Event trigger order not guaranteed
   - space_change and space_mode_refresh might fire in either order

---

## 13. Recommendations for Hardening

1. **Add File Locking:** Use flock(2) for state.json writes
2. **Atomic Writes:** Write to temp file, then rename
3. **Event Ordering:** Use explicit sequencing instead of triggers
4. **Input Validation:** Validate all state.json input in Lua/C
5. **Logging:** Add comprehensive logging to /tmp/sketchybar_debug.log
6. **Timeout Handling:** Add timeout to all Yabai queries
7. **State Versioning:** Add version field to state.json for migration
8. **Error Recovery:** Graceful degradation if state.json corrupted

---

## 14. Key Files Summary

| File | Lines | Purpose | Update Frequency |
|------|-------|---------|------------------|
| main.lua | 811 | Configuration entry point | On reload |
| modules/state.lua | 328 | State management API | On config change |
| modules/icons.lua | 411 | Icon library (legacy) | Rarely |
| modules/icon_manager.lua | 292 | Icon management (modern) | Rarely |
| modules/menu.lua | 444 | Menu rendering system | On reload |
| plugins/spaces_setup.sh | 143 | Space initialization | On space create/destroy |
| plugins/space.sh | 207 | Per-space updates | On space_change events |
| plugins/front_app.sh | 37 | Front app widget | On front_app_switched |
| helpers/popup_hover.c | 93 | Menu hover highlighting | On mouse events |
| helpers/submenu_hover.c | 162 | Submenu coordination | On mouse events |
| helpers/popup_guard.c | 41 | Parent popup guard | On mouse.exited |
| gui/config_menu_v2.m | 1562 | Configuration UI | On user interaction |

