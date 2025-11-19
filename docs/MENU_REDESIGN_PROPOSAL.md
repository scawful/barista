# Menu UX Redesign Proposal

## Problem Statement

Current nested submenu system has race conditions, flickering, and unreliable hover behavior. Users want a simpler, more reliable interface.

## Solution: Flat Menu + Popups/Widgets

### Core Principles

1. **Flat root menu only** - No nested submenus
2. **Popups for complex actions** - Configuration, settings, multi-step actions
3. **Widgets for status/info** - Real-time information displays
4. **Quick actions in root** - Most common actions directly accessible

## Proposed Menu Structure

### Root Control Center Menu (Flat)

```
┌─────────────────────────────────┐
│ 󱓞 Control Center               │
├─────────────────────────────────┤
│ System                          │
│ 󰋗 About This Mac               │
│  System Settings…             │
│ 󰜏 Force Quit…                 │
│ ─────────────────────────────   │
│ Quick Actions                   │
│ 󰒓 Control Panel…              │
│ 󰑐 Reload Bar                   │
│ 󰍛 Follow Logs                 │
│ ─────────────────────────────   │
│ Workspaces                      │
│ 󰊕 ROM Hacking…                │
│ 󰘔 Emacs Workspace…            │
│ 󱓷 halext-org…                 │
│ ─────────────────────────────   │
│ Apps                            │
│ 󰖟 Apps & Tools…               │
│ 󰙨 Dev Utilities…              │
│ ─────────────────────────────   │
│ Help                            │
│ 󰋖 Help & Tips…                │
│ 󰳟 Launch Agents…              │
│ 󰃤 Debug Tools…                │
└─────────────────────────────────┘
```

### Popup-Based Actions

Instead of submenus, clicking items with "…" opens focused popups:

#### 1. **Control Panel Popup** (Already exists!)
- Opens the unified config window
- All 11 tabs accessible
- No submenu needed

#### 2. **ROM Hacking Popup**
```
┌─────────────────────────────┐
│ 󰊕 ROM Hacking              │
├─────────────────────────────┤
│ 󰯙 Launch Yaze              │
│ 󰋜 Open Yaze Repo            │
│ 󰊕 ROM Workflow Doc         │
│ 󰘔 Focus Emacs Space        │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 3. **Emacs Workspace Popup**
```
┌─────────────────────────────┐
│ 󰘔 Emacs Workspace           │
├─────────────────────────────┤
│ Launch Emacs                 │
│ 󰩹 Tasks.org                 │
│ Focus Emacs Space            │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 4. **halext-org Popup**
```
┌─────────────────────────────┐
│ 󱓷 halext-org                │
├─────────────────────────────┤
│ View Tasks                  │
│ View Calendar               │
│ 󰚩 LLM Suggestions          │
│ ─────────────────────────   │
│ 󰑐 Refresh Data              │
│ Configure Integration       │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 5. **Apps & Tools Popup**
```
┌─────────────────────────────┐
│ 󰖟 Apps & Tools             │
├─────────────────────────────┤
│ 󰓇 App Store                │
│  Terminal                  │
│  Finder                    │
│ 󰨞 VS Code                  │
│ 󰨇 Activity Monitor         │
│ 󰯙 Yaze                     │
│ 󰺷 Mesen                    │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 6. **Dev Utilities Popup**
```
┌─────────────────────────────┐
│ 󰙨 Dev Utilities            │
├─────────────────────────────┤
│ 󰚩 Ask Ollama               │
│ [Other dev tools...]        │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 7. **Help & Tips Popup**
```
┌─────────────────────────────┐
│ 󰋖 Help & Tips              │
├─────────────────────────────┤
│ 󰘥 Open Help Center         │
│ 󰌌 WhichKey HUD             │
│ 󰈙 WhichKey Plan            │
│ 󰈙 README                    │
│ 󰓛 Sharing Guide            │
│ 󰣖 HANDOFF Notes            │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

#### 8. **Launch Agents Popup** (Widget-based)
```
┌─────────────────────────────┐
│ 󰳟 Launch Agents            │
├─────────────────────────────┤
│ [Agent Status Widget]       │
│ • yabai: ● Running          │
│ • skhd: ● Running           │
│ • sketchybar: ● Running     │
│ ─────────────────────────   │
│ [Restart All] [Stop All]    │
│ [Close]                     │
└─────────────────────────────┘
```

#### 9. **Debug Tools Popup**
```
┌─────────────────────────────┐
│ 󰃤 Debug Tools              │
├─────────────────────────────┤
│ 󰑓 Rebuild + Reload         │
│ 󰑐 Reload Bar                │
│ 󰍛 Follow Logs              │
│ 󰤘 Toggle Control Center    │
│ ─────────────────────────   │
│ [Close]                     │
└─────────────────────────────┘
```

## Implementation Strategy

### Phase 1: Remove Submenu System
1. Remove `submenu_hover.c` dependency
2. Remove `popup_guard.c` complexity
3. Simplify menu rendering

### Phase 2: Create Popup System
1. Create `popup_action.lua` - Generic popup renderer
2. Each popup is a separate SketchyBar popup item
3. Popups are self-contained and don't nest

### Phase 3: Widget Integration
1. Launch Agents status widget
2. System info widgets
3. Integration status widgets

## Technical Implementation

### New Menu Structure (menu.lua)

```lua
local control_center_items = {
  { type = "header", name = "menu.system.header", label = "System" },
  { type = "item", name = "menu.system.about", icon = "󰋗", label = "About This Mac", action = "..." },
  { type = "item", name = "menu.system.settings", icon = "", label = "System Settings…", action = "..." },
  { type = "item", name = "menu.system.forcequit", icon = "󰜏", label = "Force Quit…", action = "..." },
  { type = "separator", name = "menu.system.sep1" },
  
  { type = "header", name = "menu.quick.header", label = "Quick Actions" },
  { type = "item", name = "menu.quick.panel", icon = "󰒓", label = "Control Panel…", action = "open_popup", popup = "control_panel" },
  { type = "item", name = "menu.quick.reload", icon = "󰑐", label = "Reload Bar", action = "..." },
  { type = "item", name = "menu.quick.logs", icon = "󰍛", label = "Follow Logs", action = "..." },
  { type = "separator", name = "menu.quick.sep1" },
  
  { type = "header", name = "menu.workspaces.header", label = "Workspaces" },
  { type = "item", name = "menu.rom.popup", icon = "󰊕", label = "ROM Hacking…", action = "open_popup", popup = "rom_hacking" },
  { type = "item", name = "menu.emacs.popup", icon = "󰘔", label = "Emacs Workspace…", action = "open_popup", popup = "emacs_workspace" },
  { type = "item", name = "menu.halext.popup", icon = "󱓷", label = "halext-org…", action = "open_popup", popup = "halext_org" },
  { type = "separator", name = "menu.workspaces.sep1" },
  
  { type = "header", name = "menu.apps.header", label = "Apps" },
  { type = "item", name = "menu.apps.popup", icon = "󰖟", label = "Apps & Tools…", action = "open_popup", popup = "apps_tools" },
  { type = "item", name = "menu.dev.popup", icon = "󰙨", label = "Dev Utilities…", action = "open_popup", popup = "dev_utilities" },
  { type = "separator", name = "menu.apps.sep1" },
  
  { type = "header", name = "menu.help.header", label = "Help" },
  { type = "item", name = "menu.help.popup", icon = "󰋖", label = "Help & Tips…", action = "open_popup", popup = "help_tips" },
  { type = "item", name = "menu.agents.popup", icon = "󰳟", label = "Launch Agents…", action = "open_popup", popup = "launch_agents" },
  { type = "item", name = "menu.debug.popup", icon = "󰃤", label = "Debug Tools…", action = "open_popup", popup = "debug_tools" },
}
```

### Popup Action Handler

```lua
-- In menu_renderer.lua or new popup_action.lua
local function open_popup(popup_name)
  -- Render popup items
  local popup_items = get_popup_items(popup_name)
  render_popup(popup_name, popup_items)
  -- Show popup
  sketchybar_exec(string.format("--set %s popup.drawing=on", popup_name))
end
```

### Benefits

1. **No race conditions** - No nested hover logic needed
2. **Simpler code** - Remove submenu_hover.c complexity
3. **Better UX** - Clear, predictable behavior
4. **Easier to extend** - Just add new popup items
5. **Widget integration** - Can embed status widgets in popups

## Migration Plan

1. **Create popup renderer** - `modules/popup_action.lua`
2. **Update menu.lua** - Remove submenu types, add popup actions
3. **Create popup items** - One SketchyBar item per popup
4. **Remove submenu code** - Delete submenu_hover.c, simplify popup_guard.c
5. **Test and refine** - Ensure all actions work correctly

## Example: ROM Hacking Popup Implementation

```lua
-- In menu.lua
local function render_rom_hacking_popup(ctx)
  local items = rom_hacking_items(ctx)  -- Reuse existing function
  -- Render as popup instead of submenu
  sbar.add("item", "popup.rom_hacking", {
    popup = {
      drawing = false,
      background = { ... }
    }
  })
  -- Add items to popup
  for _, item in ipairs(items) do
    sbar.add("item", "popup.rom_hacking." .. item.name, {
      parent = "popup.rom_hacking",
      -- ... item config
    })
  end
end
```

## Next Steps

1. Review and approve this design
2. Implement popup renderer
3. Migrate menu structure
4. Remove submenu system
5. Test and refine

