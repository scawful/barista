# Menu Migration Plan: Submenus → Popups

## Overview

Migrate from nested submenu system (with race conditions) to flat menu + popup system.

## Current State

- **Nested submenus** with hover logic
- **submenu_hover.c** - Complex fork-based delayed closing
- **popup_guard.c** - Prevents parent from closing when submenu open
- **Race conditions** - Multiple forks, no PID tracking, flickering

## Target State

- **Flat root menu** - No nesting
- **Popup-based actions** - Separate popups for complex actions
- **No hover logic needed** - Click to open, click outside to close
- **Simple and reliable** - No race conditions

## Migration Steps

### Step 1: Create Popup Action Module ✅
- [x] Create `modules/popup_action.lua`
- [x] Define popup structure
- [x] Create render functions

### Step 2: Update Menu Structure
- [ ] Modify `modules/menu.lua`
- [ ] Remove `type = "submenu"` items
- [ ] Replace with `type = "item"` with `action = "open_popup"`
- [ ] Keep all existing item functions (rom_hacking_items, etc.)

### Step 3: Update Menu Renderer
- [ ] Modify `modules/menu_renderer.lua`
- [ ] Add popup rendering support
- [ ] Handle `open_popup` actions
- [ ] Remove submenu rendering code

### Step 4: Remove Submenu System
- [ ] Remove `submenu_hover.c` from build
- [ ] Simplify or remove `popup_guard.c`
- [ ] Remove submenu hover scripts
- [ ] Update `main.lua` to remove submenu subscriptions

### Step 5: Test & Refine
- [ ] Test all popups open/close correctly
- [ ] Verify all actions work
- [ ] Check performance
- [ ] Refine UX as needed

## Code Changes

### menu.lua Changes

**Before:**
```lua
{ type = "submenu", name = "menu.rom.section", icon = "󰊕", label = "ROM Hacking", items = rom_hacking_items(ctx) },
```

**After:**
```lua
{ type = "item", name = "menu.rom.popup", icon = "󰊕", label = "ROM Hacking…", action = "open_popup", popup = "rom_hacking" },
```

### menu_renderer.lua Changes

**Add:**
```lua
local popup_action = require("popup_action")

-- In render function
if item.action == "open_popup" then
  local popup_id = item.popup
  -- Set click action to open popup
  click_script = string.format('lua %s', popup_action.open_popup(popup_id, ctx))
end
```

### main.lua Changes

**Remove:**
```lua
-- Remove submenu hover subscriptions
-- Remove popup_guard complexity
```

**Add:**
```lua
-- Simple popup click handlers
-- No hover logic needed
```

## Testing Checklist

- [ ] Control Panel opens correctly
- [ ] ROM Hacking popup works
- [ ] Emacs Workspace popup works
- [ ] halext-org popup works
- [ ] Apps & Tools popup works
- [ ] Dev Utilities popup works
- [ ] Help & Tips popup works
- [ ] Launch Agents popup works
- [ ] Debug Tools popup works
- [ ] All actions within popups work
- [ ] Popups close correctly
- [ ] No flickering or race conditions
- [ ] Performance is acceptable

## Rollback Plan

If issues arise:
1. Keep old submenu code in git
2. Can revert menu.lua changes
3. Can re-enable submenu_hover.c if needed
4. Gradual migration possible (some popups, some submenus)

## Benefits

1. **No race conditions** - Simple click-based system
2. **Easier to debug** - Clear state, no forks
3. **Better UX** - Predictable behavior
4. **Simpler code** - Less complexity
5. **Easier to extend** - Just add new popup

## Timeline

- **Phase 1** (1-2 hours): Create popup system, update menu structure
- **Phase 2** (1 hour): Remove submenu code, test
- **Phase 3** (30 min): Refine and polish

Total: ~3 hours of work

