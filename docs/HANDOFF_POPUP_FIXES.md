# Handoff: Popup Menu Fixes

## Status: Partially Implemented - Needs Fixes

The menu system has been migrated from nested submenus to click-based popups, but there are issues with action execution and popup closing behavior.

## Current Issues

### 1. Popup Actions Not Executing Properly

**Problem:**
- Clicking items in popups (like "Focus Emacs Space" in Emacs Workspace popup) doesn't execute the action
- Help & Tips popup items do nothing when clicked
- Actions are defined but not being wrapped/executed correctly

**Root Cause:**
- In `menu_renderer.lua`, the `add_popup_action` function creates popup items but doesn't properly pass the popup name to `wrap_action`
- The `wrap_action` function needs the popup name to close it after action execution
- Popup items are rendered but their click handlers aren't getting the correct popup context

**Location:**
- `modules/menu_renderer.lua` - `add_popup_action` function (line ~122)
- `modules/menu_renderer.lua` - `wrap_action` function (line ~72)
- `modules/menu_renderer.lua` - `add_menu_entry` function (line ~90)

### 2. Popup Closing Behavior

**Problem:**
- Popups don't close automatically after clicking an item
- User has to manually click outside or toggle the popup

**Expected Behavior:**
- Clicking an item in a popup should:
  1. Execute the action
  2. Close the popup automatically

**Current Code:**
```lua
-- In wrap_action (line 86):
return string.format("%s; sketchybar -m --set %s popup.drawing=off", entry.action, popup_name or popup)
```

**Issue:**
- When rendering items inside a popup (via `add_popup_action`), the popup name isn't being passed correctly to `wrap_action`
- The `popup_name` parameter in `wrap_action` is the parent popup, not the current popup being closed

### 3. Emacs "Focus Space" Action

**Problem:**
- "Focus Emacs Space" should focus the Emacs window/space if it exists
- Currently defined in `menu.lua` line 62:
  ```lua
  { type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs") },
  ```

**Expected:**
- Should check if Emacs is running
- If running, focus its space/window
- If not running, maybe show a message or launch it

**Current:**
- Action is defined but may not be executing due to popup action wrapping issue

### 4. Help & Tips Popup

**Problem:**
- Help & Tips popup items do nothing when clicked
- Items are loaded from `data/menu_help.json` or fallback items

**Location:**
- `modules/menu.lua` - `help_items` function (line ~93)
- `data/menu_help.json` - Help menu data

**Expected:**
- Items should open help center, whichkey, docs, etc.
- Actions are defined but not executing

## Files to Fix

### 1. `modules/menu_renderer.lua`

**Function: `add_popup_action` (line ~122)**

**Current Issue:**
```lua
-- Render items into the popup
if items and #items > 0 then
  renderer(popup_item_name, items)  -- ❌ popup_item_name is passed, but renderer needs to know this is a popup
end
```

**Fix Needed:**
- When rendering items inside a popup, need to pass the popup name to `wrap_action`
- The `render_menu_items` function calls `add_menu_entry` which calls `wrap_action`
- `wrap_action` needs to know which popup to close after action

**Solution:**
```lua
local function add_popup_action(popup, entry, renderer)
  local padding = menu_entry_padding()
  local popup_name = entry.popup or entry.name
  local items = entry.items or {}
  
  -- Create popup container item
  local popup_item_name = "popup." .. popup_name
  sbar.add("item", popup_item_name, {
    position = "left",
    icon = "",
    label = "",
    drawing = false,
    popup = {
      align = "right",
      background = {
        border_width = 2,
        corner_radius = 4,
        border_color = theme.WHITE,
        color = theme.bar.bg
      }
    }
  })
  
  -- Render items into the popup - pass popup name in context
  if items and #items > 0 then
    -- Create a wrapper renderer that knows about this popup
    local function popup_renderer(target_popup, entries)
      for _, item in ipairs(entries) do
        if item.type == "item" then
          -- Add popup close to action
          local action = item.action or ""
          if action ~= "" then
            item.action = string.format("%s; sketchybar -m --set %s popup.drawing=off", action, popup_item_name)
          end
        end
      end
      renderer(target_popup, entries)
    end
    popup_renderer(popup_item_name, items)
  end
  
  -- Create clickable menu item that opens the popup
  local click_action = string.format(
    "sketchybar -m --set %s popup.drawing=toggle",
    popup_item_name
  )
  
  sbar.add("item", entry.name, {
    position = "popup." .. popup,
    icon = entry.icon or "",
    label = entry.label or "",
    click_script = click_action,
    script = ctx.HOVER_SCRIPT,
    -- ... rest of config
  })
  attach_hover(entry.name)
end
```

**Function: `wrap_action` (line ~72)**

**Current Issue:**
- Doesn't properly handle popup closing when action is in a popup
- The `popup_name` parameter might be the wrong popup

**Fix Needed:**
- Need to track which popup an item belongs to
- Close the correct popup after action

**Alternative Solution:**
- Modify `add_menu_entry` to accept a `parent_popup` parameter
- Pass this through to `wrap_action`
- Close the parent popup after action

### 2. `modules/menu.lua`

**Function: `emacs_items` (line ~47)**

**Current:**
```lua
{ type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs") },
```

**Enhancement Needed:**
- Add check if Emacs is running before trying to focus
- Maybe show feedback if Emacs isn't running

**Suggested Fix:**
```lua
local function focus_emacs_space()
  -- Check if Emacs is running
  local check_cmd = "pgrep -x Emacs > /dev/null"
  local emacs_running = os.execute(check_cmd) == 0
  
  if emacs_running then
    return ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs")
  else
    return "osascript -e 'display notification \"Emacs is not running\" with title \"Focus Emacs\"'"
  end
end

{ type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_space() },
```

### 3. `modules/menu_renderer.lua`

**Function: `add_menu_entry` (line ~90)**

**Fix Needed:**
- Accept optional `parent_popup` parameter
- Pass to `wrap_action` so it can close the correct popup

**Solution:**
```lua
local function add_menu_entry(popup, entry, parent_popup)
  parent_popup = parent_popup or popup  -- Default to current popup
  local padding = menu_entry_padding()
  local label = menu_label(entry.label, entry.shortcut)
  local click = wrap_action(entry, parent_popup)  -- Pass parent popup
  
  -- ... rest of function
end
```

**Update `render_menu_items` to pass parent popup:**
```lua
local function render_menu_items(popup, entries, parent_popup)
  parent_popup = parent_popup or popup
  for _, entry in ipairs(entries or {}) do
    if entry.type == "header" then
      add_menu_header(popup, entry)
    elseif entry.type == "separator" then
      add_menu_separator(popup, entry)
    elseif entry.popup then
      add_popup_action(popup, entry, function(target, items)
        render_menu_items(target, items, target)  -- Pass target as parent
      end)
    else
      add_menu_entry(popup, entry, parent_popup)  -- Pass parent popup
    end
  end
end
```

## Testing Checklist

After fixes, test:

- [ ] Click "ROM Hacking…" → Popup opens
- [ ] Click "Launch Yaze" in ROM popup → Action executes, popup closes
- [ ] Click "Emacs Workspace…" → Popup opens
- [ ] Click "Focus Emacs Space" → Focuses Emacs if running, popup closes
- [ ] Click "Help & Tips…" → Popup opens
- [ ] Click any Help item → Action executes, popup closes
- [ ] Click "Apps & Tools…" → Popup opens
- [ ] Click any app → App opens, popup closes
- [ ] All popups close after clicking an item
- [ ] No actions execute without closing popup

## Implementation Steps

1. **Fix popup action wrapping:**
   - Modify `add_popup_action` to properly close popup after action
   - Update `render_menu_items` to track parent popup
   - Update `add_menu_entry` to accept parent popup parameter

2. **Enhance Emacs focus:**
   - Add check if Emacs is running
   - Provide feedback if not running

3. **Test all popups:**
   - Verify all actions execute
   - Verify popups close after actions
   - Check for any remaining issues

4. **Clean up:**
   - Remove any debug code
   - Ensure consistent behavior across all popups

## Related Files

- `modules/menu.lua` - Menu item definitions
- `modules/menu_renderer.lua` - Rendering logic (main fix needed here)
- `data/menu_help.json` - Help menu data
- `plugins/menu_action.sh` - Action execution script (may need updates)

## Notes

- The popup system is working structurally (popups open/close)
- The issue is with action execution and popup closing after actions
- All the action strings are correct, they just need proper wrapping
- The `wrap_action` function exists but isn't getting the right popup context

## Quick Fix Summary

**Main Issue:** Popup items don't close their parent popup after executing actions.

**Solution:** Pass the popup name through the rendering chain so `wrap_action` can close it.

**Key Change:** Modify `add_popup_action` to inject popup closing into item actions, or update `render_menu_items` to track and pass parent popup context.

---

## Remaining TODOs from Today's Session

### High Priority (Popup System)

1. **Fix Popup Action Execution** ⚠️
   - **Status:** Pending
   - **Issue:** Items in popups not executing actions, popups not closing after actions
   - **Files:** `modules/menu_renderer.lua` (add_popup_action, wrap_action, add_menu_entry)
   - **Details:** See "Current Issues" section above

2. **Fix Emacs Focus Action** ⚠️
   - **Status:** Pending
   - **Issue:** "Focus Emacs Space" should check if Emacs is running before focusing
   - **Files:** `modules/menu.lua` (emacs_items function, line ~47)
   - **Enhancement:** Add pgrep check, show notification if Emacs not running

3. **Fix Help & Tips Popup** ⚠️
   - **Status:** Pending
   - **Issue:** Help & Tips popup items do nothing when clicked
   - **Files:** `modules/menu.lua` (help_items function, line ~93), `data/menu_help.json`
   - **Details:** Actions defined but not executing - same root cause as #1

### Medium Priority (Code Quality)

4. **Refactor Menu Rendering** 📝
   - **Status:** Pending
   - **Task:** Consolidate structure, improve API, add validation
   - **Files:** `modules/menu.lua`, `modules/menu_renderer.lua`
   - **Notes:** After popup fixes are working, clean up and refactor

5. **Refactor State Management** 📝
   - **Status:** Pending
   - **Task:** Add validation, atomic writes, versioning, error recovery
   - **Files:** `modules/state.lua`
   - **Notes:** Improve robustness of state.json handling

6. **Update main.lua for Theme Integration** 📝
   - **Status:** Pending
   - **Task:** Load theme from state.json and integrate with new unified config window
   - **Files:** `main.lua`
   - **Dependencies:** Config window must be working first

### Low Priority (Cleanup - May Be Obsolete)

7. **Fix Submenu Race Conditions** 🗑️
   - **Status:** Pending (May be obsolete)
   - **Task:** Add PID tracking, file locking, cancellation mechanism
   - **Files:** `helpers/submenu_hover.c`
   - **Notes:** Only needed if reverting to submenu system. Popup system should replace this.

8. **Improve Submenu UX** 🗑️
   - **Status:** Pending (May be obsolete)
   - **Task:** Configurable delays, expanded hover zones, smoother transitions
   - **Files:** `helpers/submenu_hover.c`, `helpers/popup_guard.c`
   - **Notes:** Only needed if reverting to submenu system. Popup system should replace this.

9. **Remove Submenu Code** 🗑️
   - **Status:** Pending
   - **Task:** Remove submenu_hover.c and simplify popup_guard.c once popup system is fully working
   - **Files:** `helpers/submenu_hover.c`, `helpers/popup_guard.c`, `main.lua` (remove subscriptions)
   - **Dependencies:** Popup system must be fully working and tested

### Testing & Validation

10. **Test New Config Window** ✅
    - **Status:** Pending
    - **Task:** Verify all tabs work, theme switching, shortcuts viewer, icon browser integration
    - **Files:** `build/bin/config_menu` (GUI binary)
    - **Notes:** Config window is built but needs integration testing

## Priority Order

1. **Fix popup actions** (Blocks everything else)
2. **Fix Emacs focus** (User-requested enhancement)
3. **Fix Help & Tips** (Same root cause as #1)
4. **Test config window** (Verify it works)
5. **Update main.lua theme integration** (Feature completion)
6. **Refactor menu/state** (Code quality)
7. **Remove submenu code** (Cleanup after popups work)
8. **Submenu fixes** (Only if reverting - unlikely)

## Estimated Time

- **Popup fixes (#1-3):** 2-3 hours
- **Config window testing (#10):** 30 minutes
- **Theme integration (#6):** 1 hour
- **Refactoring (#4-5):** 2-3 hours
- **Cleanup (#7-9):** 1 hour

**Total:** ~6-8 hours of focused work

