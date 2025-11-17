# System Fixes Implementation

**Date:** November 17, 2025
**Based on:** ARCHITECTURE_ANALYSIS.md findings
**Priority:** Critical bugs first

## Issues Identified & Solutions

### 1. Apple Menu Icon Not Displaying ⚠️ CRITICAL

**Problem:**
- Icon shows as empty or not visible
- c_bridge.icons.get() may return empty string
- Post-initialization override may conflict

**Root Cause:**
- Icon resolution timing issue
- Font loading race condition
- Multiple icon-setting calls conflicting

**Solution:**
```lua
-- In main.lua line 335, replace with:
icon = {
  value = "",  -- Direct Apple icon glyph
  font = "Hack Nerd Font:Bold:18.0",  -- Explicit font
  drawing = true,
  color = theme.WHITE
},
```

**Also remove lines 803-808** (conflicting post-init override):
```lua
-- DELETE THESE LINES:
local apple_icon_value = state_module.get_icon(state, "apple")
if apple_icon_value and apple_icon_value ~= "" then
  sbar.exec(string.format("sketchybar --set apple_menu icon='%s'", apple_icon_value))
end
```

---

### 2. Submenu Hover Behavior Broken ⚠️ HIGH

**Problem:**
- Submenus don't respond to hover properly
- `/tmp/sketchybar_submenu_state` timing race
- Background process cleanup issues

**Root Cause** (from architecture analysis):
```
submenu_hover.c spawns background sleep process
  ↓
Parent exits immediately (returns control to bar)
  ↓
Child process orphaned, cleanup timing undefined
  ↓
State file may persist or be cleaned too early
```

**Solution:**
Fix `helpers/submenu_hover.c` to use proper daemonization:

```c
// Replace fork() logic with proper daemon:
pid_t pid = fork();
if (pid < 0) {
    return 1;  // Fork failed
}
if (pid > 0) {
    // Parent: wait briefly for child to initialize
    usleep(10000);  // 10ms
    exit(0);
}

// Child: become session leader
setsid();

// Continue with hover logic...
```

Also add cleanup handler:
```c
void cleanup_handler(int sig) {
    if (state_file) {
        unlink(state_file);
    }
    exit(0);
}

signal(SIGTERM, cleanup_handler);
signal(SIGINT, cleanup_handler);
```

---

### 3. Spaces Tab Crashes Control Panel ⚠️ HIGH

**Problem:**
- Spaces tab causes config_menu_v2 to crash
- Likely accessing freed memory or nil reference

**Root Cause:**
- SpacesTabController may not check if space data exists
- yabai query might return empty/invalid JSON
- Tab switching doesn't validate data first

**Solution:**
In `gui/config_menu_v2.m`, add null checks:

```objc
- (void)loadSpacesTab {
    // Add validation
    if (!self.configManager || !self.configManager.state) {
        NSLog(@"Config manager not initialized");
        return;
    }

    NSDictionary *spaces = self.configManager.state[@"space_icons"];
    if (!spaces || ![spaces isKindOfClass:[NSDictionary class]]) {
        spaces = @{};  // Empty dict as fallback
    }

    // Continue with UI population...
}
```

---

### 4. Space Loading Lag ⚠️ HIGH

**Problem:**
- Spaces take time to load/refresh
- Icons switch between numbers and icons
- Async yabai commands without synchronization

**Root Cause:**
```
main.lua calls plugins/spaces_setup.sh
  ↓
Script runs yabai -m query (async, ~50-100ms)
  ↓
Script generates item creation commands
  ↓
Each space item created individually (not batched)
  ↓
Total time: N_spaces × (query_time + create_time)
```

**Solution 1: Batch Space Creation**

Create `plugins/spaces_setup_fast.sh`:
```bash
#!/bin/bash

# Query once, create all items in single sketchybar invocation
SPACES_JSON=$(yabai -m query --spaces 2>/dev/null || echo '[]')

# Build batch command
CMD="sketchybar"

echo "$SPACES_JSON" | jq -r '.[] | @json' | while read -r space; do
  SPACE_ID=$(echo "$space" | jq -r '.index')
  SPACE_LABEL=$(echo "$space" | jq -r '.label // ""')
  IS_VISIBLE=$(echo "$space" | jq -r '.["is-visible"] // false')

  # Add to batch command
  CMD="$CMD --add space space_${SPACE_ID} left"
  CMD="$CMD --set space_${SPACE_ID} icon=${SPACE_ID} label='${SPACE_LABEL}'"

  if [ "$IS_VISIBLE" = "true" ]; then
    CMD="$CMD --set space_${SPACE_ID} background.color=0xFF89b4fa"
  fi
done

# Execute single batch command
eval "$CMD"
```

**Solution 2: Pre-cache Space Data**

In `modules/state.lua`, add space caching:
```lua
-- Cache space data to avoid repeated yabai queries
local space_cache = {
  data = nil,
  timestamp = 0,
  ttl = 5  -- 5 second cache
}

function state.get_spaces()
  local now = os.time()
  if space_cache.data and (now - space_cache.timestamp) < space_cache.ttl then
    return space_cache.data
  end

  -- Query and cache
  local handle = io.popen("yabai -m query --spaces 2>/dev/null")
  local output = handle:read("*a")
  handle:close()

  space_cache.data = output
  space_cache.timestamp = now
  return output
end
```

---

### 5. Front App Widget Not Refreshing ⚠️ MEDIUM

**Problem:**
- App icon/name doesn't update when switching apps
- Sporadic updates, sometimes shows old app

**Root Cause:**
- `front_app_switched` event may not always fire
- Shell script `front_app.sh` has delays
- `app_icon.sh` Python parsing adds latency

**Solution 1: Use C Widget**

Create `helpers/front_app_widget.c`:
```c
#include <ApplicationServices/ApplicationServices.h>

// Get frontmost app directly
void get_front_app(char* name, char* icon) {
    ProcessSerialNumber psn;
    GetFrontProcess(&psn);

    CFStringRef app_name;
    CopyProcessName(&psn, &app_name);

    // Convert to C string
    CFStringGetCString(app_name, name, 256, kCFStringEncodingUTF8);

    // Get icon from icon_manager
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "~/.config/sketchybar/bin/icon_manager get '%s' '󰣆'",
             name);

    FILE* fp = popen(cmd, "r");
    if (fp) {
        fgets(icon, 16, fp);
        pclose(fp);
    }

    CFRelease(app_name);
}
```

**Solution 2: Increase Update Frequency**

In `main.lua`, change front_app to poll more frequently:
```lua
sbar.add("item", "front_app", {
  -- ... existing config ...
  update_freq = 1,  -- Poll every second instead of event-only
  script = PLUGIN_DIR .. "/front_app.sh"
})
```

---

### 6. Icons Switching Between Numbers and Icons ⚠️ MEDIUM

**Problem:**
- Space icons show as numbers "1", "2", "3" then switch to icons
- Inconsistent icon display across reloads

**Root Cause:**
```
spaces_setup.sh runs async
  ↓
Initial space items created with icon=${SPACE_ID} (number)
  ↓
Later, space icon assignment runs from state.json
  ↓
Race condition: which completes first?
```

**Solution:**

Modify `plugins/spaces_setup.sh` to read icons from state immediately:
```bash
#!/bin/bash

STATE_FILE="$HOME/.config/sketchybar/state.json"

# Read space icons from state
get_space_icon() {
  local space_num=$1
  if [ -f "$STATE_FILE" ]; then
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        data = json.load(f)
    icons = data.get('space_icons', {})
    print(icons.get('$space_num', '$space_num'))
except:
    print('$space_num')
"
  else
    echo "$space_num"
  fi
}

# Use icon from state when creating spaces
yabai -m query --spaces | jq -r '.[] | @json' | while read -r space; do
  SPACE_ID=$(echo "$space" | jq -r '.index')
  SPACE_ICON=$(get_space_icon "$SPACE_ID")

  sketchybar --add space space_${SPACE_ID} left \
             --set space_${SPACE_ID} icon="$SPACE_ICON" \
             # ... rest of config
done
```

---

## Implementation Priority

### Phase 1: Critical Fixes (Do First)
1. ✅ Apple menu icon - direct glyph assignment
2. ✅ Remove conflicting post-init override
3. ✅ Fix spaces tab crash - add null checks
4. ✅ Space icon race condition - read from state immediately

### Phase 2: Performance Improvements
5. ⏳ Batch space creation - single sketchybar command
6. ⏳ Add space data caching - reduce yabai queries
7. ⏳ Front app C widget - eliminate shell overhead

### Phase 3: Quality of Life
8. ⏳ Submenu hover daemon - proper cleanup
9. ⏳ Front app polling - more frequent updates
10. ⏳ Icon gallery in control panel

---

## Testing Plan

### After Each Fix:
```bash
# Reload bar
sketchybar --reload

# Verify apple icon
sketchybar --query apple_menu | grep icon

# Test spaces
yabai -m space --focus 1
yabai -m space --focus 2

# Test front app
# (switch between apps manually)

# Test control panel
~/.config/sketchybar/gui/bin/config_menu_v2
# Navigate to Spaces tab
```

### Integration Test:
1. Restart yabai: `yabai --restart-service`
2. Reload SketchyBar: `sketchybar --reload`
3. Open control panel, test all tabs
4. Switch spaces rapidly (1→2→3→1)
5. Switch apps rapidly
6. Hover over submenus

---

## Rollback Plan

If fixes cause issues:
```bash
# Revert main.lua
git checkout HEAD~1 main.lua

# Rebuild old binaries
cd helpers && git checkout HEAD~1 *.c && make clean && make install

# Reload
sketchybar --reload
```

---

## Related Documentation

- [Architecture Analysis](ARCHITECTURE_ANALYSIS.md) - Root cause analysis
- [Icon Reference](ICON_REFERENCE.md) - Icon system guide
- [Architecture README](ARCHITECTURE_README.md) - System overview

---

**Status:** Ready for implementation
**Estimated Time:** 2-3 hours
**Risk Level:** Medium (test each fix individually)
