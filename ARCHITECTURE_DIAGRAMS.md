# SketchyBar Architecture Diagrams

## System Component Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    macOS System Events                              │
│  (Yabai signals, mouse events, window changes, etc.)               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
         ┌───────────────┴──────────────────┐
         │                                  │
         ▼                                  ▼
    SketchyBar Core                   Yabai WM
    (Event dispatcher)                (Space/Window mgmt)
         │                                  │
         │                                  │
         ▼                                  ▼
    Lua Configuration              Yabai Signals
    (main.lua)                    (space_changed, etc.)
    │
    ├─ modules/state.lua ──► ~/.config/sketchybar/state.json
    ├─ modules/icons.lua ──┐
    ├─ modules/menu.lua    ├─► Widget/Menu Rendering
    └─ modules/widgets.lua ┘
    │
    ├─ plugins/*.sh (Shell scripts)
    │   ├─ space.sh
    │   ├─ front_app.sh
    │   ├─ spaces_setup.sh
    │   └─ set_space_mode.sh
    │
    ├─ C Bridge & Components
    │   ├─ modules/c_bridge.lua ──► ~/.config/sketchybar/bin/*
    │   └─ modules/component_switcher.lua
    │
    └─ GUI Configuration
        └─ gui/config_menu_v2.m
            (ConfigurationManager → state.json)

    C Helpers (in helpers/)
    ├─ popup_hover.c ◄──┐
    ├─ submenu_hover.c  ├─ /tmp state files
    └─ popup_guard.c  ◄─┘
```

## Event Flow: Space Creation

```
┌─────────────────┐
│  Yabai Creates  │
│  New Space      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Yabai Signal: event=space_created       │
│ Action: refresh_spaces.sh               │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ plugins/refresh_spaces.sh               │
│ • Calls: spaces_setup.sh                │
│ • Updates external bar height (optional)│
└────────┬────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────┐
│ plugins/spaces_setup.sh                            │
│ 1. Remove existing space.* items                   │
│ 2. Query: yabai -m query --spaces                  │
│ 3. Read: ~/.config/sketchybar/state.json           │
│    └─ Extract space_icons dict                     │
│ 4. Create space items:                             │
│    • Set icon (priority: state > default)          │
│    • Subscribe to: mouse.entered, mouse.exited,    │
│                    space_change, space_mode_refresh│
│    • Attach: space.sh script                       │
│ 5. Create space_creator button                     │
└────────┬───────────────────────────────────────────┘
         │
         ▼ (subsequent space_change event)
┌────────────────────────────────────────────────────┐
│ plugins/space.sh (runs for EACH space)             │
│                                                    │
│ Triggers: space_change, space_mode_refresh,       │
│           mouse.entered, mouse.exited              │
│                                                    │
│ Operations:                                        │
│ 1. Read state.json:                                │
│    • space_icons.<N> (custom icon)                 │
│    • space_modes.<N> (desired layout)              │
│                                                    │
│ 2. ensure_space_layout():                          │
│    • Query: yabai -m query --spaces --space <N>    │
│    • Compare: desired vs current layout             │
│    • If mismatch: yabai -m space <N> --layout <M> │
│                                                    │
│ 3. Icon selection (if not mouse hover):            │
│    • Custom icon from state.json                   │
│    • OR query: yabai -m query --windows --space <N>│
│    • OR resolve app icon via app_icon.sh           │
│    • OR show • (active) or ○ (inactive)            │
│                                                    │
│ 4. Update widget:                                  │
│    sketchybar --set space.<N> icon="..." ...       │
│                                                    │
│ 5. Hover effects:                                  │
│    • mouse.entered: show background, highlight    │
│    • mouse.exited: restore colors                  │
└─────────────────────────────────────────────────────┘
         │
         ▼
    SketchyBar Bar Updates
    (visual refresh on screen)
```

## Icon Resolution Chain

```
┌─────────────────────────────────────────┐
│ Request: icon_for(name, fallback)       │
│ (From main.lua line 151)                │
└────────┬────────────────────────────────┘
         │
         ▼
    ┌────────────────────────────────┐
    │ Step 1: Check State Icons      │
    │ • Read: state.icons[name]      │
    │ • Validate: UTF-8 check        │
    │ • If valid: RETURN icon        │
    └────────┬───────────────────────┘
             │ (not found or invalid)
             ▼
    ┌────────────────────────────────┐
    │ Step 2: Icon Manager           │
    │ • Call: icon_manager.get_char()│
    │ • Check library (Hack Nerd +   │
    │   fallback fonts)              │
    │ • If found: RETURN icon        │
    └────────┬───────────────────────┘
             │ (not found)
             ▼
    ┌────────────────────────────────┐
    │ Step 3: Legacy Icons Module    │
    │ • Call: icons_module.find()    │
    │ • Search all categories        │
    │ • If found: RETURN icon        │
    └────────┬───────────────────────┘
             │ (not found)
             ▼
    ┌────────────────────────────────┐
    │ Step 4: Fallback               │
    │ • RETURN provided fallback icon│
    │ • Or empty string if no icon   │
    └────────────────────────────────┘
```

## Space Icon Update: GUI Path

```
┌──────────────────────────────────────┐
│ User: GUI Config Panel               │
│ (gui/config_menu_v2.m)               │
│                                      │
│ 1. Select space in SpacesTab         │
│ 2. Enter custom icon                 │
│ 3. Click "Apply to Current Space"    │
└────────┬─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ SpacesTabViewController.applySettings│
│ • Save: space_icons.<N> = icon       │
│ • Save: space_modes.<N> = mode       │
└────────┬─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│ ConfigurationManager.setValue()      │
│ • Write state.json atomically        │
│ • If mode changed:                   │
│   └─ Call set_space_mode.sh          │
└────────┬─────────────────────────────┘
         │
    ┌────┴──────────────────────────┐
    │                               │
    ▼                               ▼
set_space_mode.sh              reloadSketchyBar
• Update state.json            • sketchybar --reload
• yabai -m space <N>
  --layout <mode>
• Trigger:
  space_mode_refresh
  yabai_status_refresh
    │                               │
    └────────┬──────────────────────┘
             │
             ▼
    ┌──────────────────────────────┐
    │ main.lua (re-evaluated)      │
    │ • Load new state.json        │
    │ • Re-subscribe to events     │
    │ • Plugin scripts attached    │
    └────────┬─────────────────────┘
             │
             ▼
    ┌──────────────────────────────┐
    │ space.sh (runs via triggers) │
    │ • Reads updated state.json   │
    │ • Updates icon display       │
    │ • Ensures Yabai in sync      │
    └────────┬─────────────────────┘
             │
             ▼
         Bar Refreshes
    (new space icon visible)
```

## Menu System: Submenu Hover Coordination

```
┌─────────────────────────────────────────────────┐
│ User hovers on Submenu Parent                   │
│ Example: "Sketchybar Settings"                  │
└────────┬────────────────────────────────────────┘
         │
         ▼ (mouse.entered event)
┌────────────────────────────────────────────────────┐
│ submenu_hover.c (SUBMENU_HOVER_SCRIPT)             │
│                                                    │
│ Actions on mouse.entered:                          │
│ 1. Close OTHER open submenus (batch command)      │
│ 2. Write: /tmp/sketchybar_submenu_active = name  │
│ 3. Write: /tmp/sketchybar_parent_popup_lock      │
│    (prevents parent from closing)                 │
│ 4. sketchybar --set <name> popup.drawing=on      │
│ 5. Set background.color=HOVER_BG (0x80cba6f7)    │
└────────┬───────────────────────────────────────────┘
         │
         ▼ (submenu now visible)
    ┌────────────────────────────────┐
    │ User interacts with submenu    │
    │ Can read menu items, etc.      │
    └────────┬─────────────────────────┘
             │
             ▼ (user moves out)
    ┌────────────────────────────────┐
    │ submenu_hover.c                │
    │ (mouse.exited event)           │
    │                                │
    │ Actions:                        │
    │ 1. fork() background process   │
    │ 2. Wait CLOSE_DELAY (0.25s)    │
    │ 3. Check: is submenu still     │
    │    active? (read /tmp file)    │
    │ 4. If NOT active:              │
    │    Close submenu popup         │
    │    Clean up /tmp files         │
    └────────┬─────────────────────────┘
             │ (0.25s delay)
             │
             ▼ (background process runs)
    ┌────────────────────────────────┐
    │ If submenu no longer active:   │
    │ • /tmp/sketchybar_submenu_     │
    │   active deleted               │
    │ • Parent popup lock removed    │
    │                                │
    │ Parent popup mouse.exited now  │
    │ can proceed to closing         │
    └────────┬─────────────────────────┘
             │
             ▼
    ┌────────────────────────────────┐
    │ Parent menu's mouse.exited     │
    │                                │
    │ popup_guard.c checks:          │
    │ • Does lock file exist?        │
    │   /tmp/.../parent_popup_lock   │
    │                                │
    │ If EXISTS: do nothing          │
    │   (submenu still open)         │
    │                                │
    │ If NOT EXISTS:                 │
    │   Close parent popup           │
    │   sketchybar --set apple_menu  │
    │   popup.drawing=off            │
    └────────────────────────────────┘
         │
         ▼
    Parent menu closes
```

## Data Synchronization Points

```
┌─────────────────────────────────────────────┐
│ ~/.config/sketchybar/state.json             │
│ (Central persistent state)                  │
├─────────────────────────────────────────────┤
│ {                                           │
│   "widgets": {...},                         │
│   "appearance": {...},                      │
│   "icons": {                                │
│     "apple": "custom_icon",                 │
│     ...                                     │
│   },                                        │
│   "space_icons": {                          │
│     "1": "󰀶",  ◄─── Custom icons per space │
│     "2": "󰉉"                                │
│   },                                        │
│   "space_modes": {                          │
│     "2": "bsp",  ◄─── Layout mode per space│
│     "3": "stack"                            │
│   },                                        │
│   "widget_colors": {...}                    │
│ }                                           │
└─────────────────────────────────────────────┘
     ▲       ▲       ▲       ▲       ▲
     │       │       │       │       │
Read │       │       │       │       │ Written by:
by:  │       │       │       │       │
     │       │       │       │       └─ set_space_mode.sh
     │       │       │       └─────── config_menu_v2.m
     │       │       └───────────── space.sh (read only)
     │       └──────────────────── spaces_setup.sh (read)
     │                            (and Python inline)
     └─ main.lua initialization
       plugins/*/sh (read)
       modules/state.lua
```

## Temporary File State Machine

```
Submenu hover state files:

/tmp/sketchybar_submenu_active
├─ Created: when submenu entered
├─ Contains: submenu name
├─ Checked: by schedule_close() background process
├─ Deleted: when submenu exited AND CLOSE_DELAY elapsed
└─ Lifetime: <250ms (0.25s default)

/tmp/sketchybar_parent_popup_lock
├─ Created: when ANY submenu entered
├─ Checked: by popup_guard.c
├─ Means: "keep parent popup open"
├─ Deleted: when all submenus closed
└─ Lifetime: while hovering + CLOSE_DELAY

/tmp/sketchybar_popup_state/active_parent
├─ Created: by popup_hover.c
├─ Contains: parent popup name
├─ Used: for submenu coordination
└─ Lifetime: duration of hover

Flow:
┌──────────────────────────────────────────────────────┐
│ User enters submenu A                                │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ Create: /tmp/sketchybar_submenu_active = "menu.A"   │
│ Create: /tmp/sketchybar_parent_popup_lock           │
└────────┬─────────────────────────────────────────────┘
         │
    ┌────┴──────────────────────────────────┐
    │ User still hovering on submenu A      │
    │ popup_guard sees lock file exists     │
    │ Parent popup stays open               │
    │                                       │
    │ (time passes...)                      │
    └────┬──────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ User exits submenu A (mouse.exited)                 │
│ schedule_close() forks background process           │
└────────┬─────────────────────────────────────────────┘
         │
         ├─ parent returns immediately
         │
         └─ child sleeps 0.25s, then checks...
            │
            ▼ (after 0.25s)
         Check: is submenu_active file still "menu.A"?
         │
         ├─ YES (user re-entered): do nothing, exit
         │
         └─ NO (still exited): 
            delete files
            close submenu popup
            exit
            │
            ▼
         Parent popup mouse.exited fires
         popup_guard checks lock file
         File missing → close parent
```

## Component Switcher Architecture

```
┌─────────────────────────────────────────────┐
│ Component Switcher (modules/)               │
│                                             │
│ Modes:                                      │
│ • "auto" ─┐   Use C if available           │
│ • "c"  ───┼─> Fallback to Lua if missing   │
│ • "lua" ──┤   Force specific impl          │
│ • "hybrid"┘   Each picks independently     │
└──────────┬──────────────────────────────────┘
           │
      ┌────┴────┐
      │          │
      ▼          ▼
   C Impl    Lua Impl
   (binary)  (module)
     │          │
     ├─ icon_manager
     ├─ state_manager
     ├─ widget_manager
     └─ menu_renderer
           │
           ▼
    Performance Tracking
    (stats in memory)
    │
    └─ get_stats() for debugging
```

---

## Configuration Flow Summary

```
User Changes → GUI (Cocoa) → state.json → Lua Re-eval → Scripts → Bar Update
   │              │             │              │           │         │
   └─ Spaces Tab  └─ ConfigMgr  └─ File I/O   └─ main.lua └─ shell └─ Icon/Mode
   └─ Appearance  └─ singleton  └─ atomic       └─ reload    └─ Python change
   └─ Icons          (dispatch)     write         └─ events   └─ Yabai
   └─ Toggles                         once        └─ subs      query


Events from System → SketchyBar → Lua Scripts → State → UI
   │                   │              │          │       │
   └─ Yabai signals   └─ trigger   └─ run  └─ read  └─ display
   └─ Mouse events      └─ subscribe └─ shell  └─ update update
   └─ App changes       └─ events      └─ Python
   └─ Volume/Battery                     inline
```

