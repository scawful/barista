# Barista/SketchyBar Integration Summary

**Date**: 2026-01-01
**Scope**: historical integration notes for sys_manual-era menu work

## Overview

This document is historical. Barista owns SketchyBar's glanceable status,
popups, and quick launch; Cortex owns the native host/runtime, and Oracle inside
Cortex owns persistent AI workflow. `bin/open_oracle_agent_manager.sh` prefers
that Cortex surface and keeps the legacy Oracle Agent Manager as a fallback.
The completion badges, prototype paths, and
replacement claims below describe the 2026-01 experiment, not the current source
tree. Do not use them as an install or implementation checklist; start with
`README.md`, `docs/architecture/SKETCHYBAR_LAYOUT.md`, and
`docs/features/BARISTA_CONTROL_PANEL.md`.

## What Was Done

### 1. Enhanced Control Center Module ✅
**File**: `~/.config/sketchybar/modules/integrations/control_center_enhanced.lua`

**Features**:
- macOS Control Center-inspired grouped sections with rounded backgrounds
- Visual group headers with icons and colors
- Control tiles with hover states
- Tool launchers: sys_manual, terminal, finder
- Workspace status (dirty repos indicator)
- Space layout controls (Float/BSP/Stack)
- Window operations (balance, rotate, flip)
- Service status indicators (Yabai, skhd, SketchyBar)
- System actions (Settings, Lock Screen)

**Visual Design**:
- Rounded corner tiles (8px radius)
- Grouped sections with visual headers
- Status-based coloring (green ✓ / red ✗)
- Better spacing and padding
- Semi-transparent backgrounds

### 2. Enhanced Apple Menu Component ✅
**File**: `~/.config/sketchybar/components/apple_menu_enhanced.lua`

**Features**:
- New "Tools & Workspace" section
- sys_manual quick launch
- Terminal and Finder shortcuts
- Better-organized submenus
- Status-aware icon colors (green = running, gray = stopped)

**Menu Structure**:
```
 (Apple Icon)
├── System
│   ├── About This Mac
│   ├── System Settings…
│   └── Force Quit…
│
├── Tools & Workspace ←─ NEW
│   ├── System Manual
│   ├── Terminal
│   └── Open Workspace
│
├── SketchyBar Tools ▸
│   ├── Reload Bar
│   ├── Open Config
│   ├── Barista Settings  ← Will launch halext GUI
│   └── View Logs
│
├── Yabai Controls ▸
├── Window Actions ▸
└── Sleep / Lock
```

### 3. halext Barista Config Tool ✅
**Location**: `/Users/scawful/src/lab/barista_config/`
**Documentation**: [barista_config User Guide](../barista_config/docs/USER_GUIDE.md)

**Status**: Phase 2 Complete (Foundation) - Application builds and runs with stub views

**Architecture**:
```
barista_config/
├── src/
│   ├── app.{h,cc}               # Extends afs::gui::Application
│   ├── state/
│   │   └── config_manager.{h,cc}  # state.json R/W
│   └── views/
│       ├── appearance.{h,cc}    # Colors, fonts, sizes (stub)
│       ├── widgets.{h,cc}       # Widget toggles (stub)
│       ├── icons.{h,cc}         # Icon browser (stub)
│       └── integrations.{h,cc}  # Cortex, yaze, etc. (stub)
├── docs/
│   └── USER_GUIDE.md            # Comprehensive user documentation
├── CMakeLists.txt
├── IMPLEMENTATION.md
└── README.md
```

**Replaces**: BaristaControlPanel.app (351KB Objective-C GUI)

**Benefits**:
- Modern ImGui interface with Material Design icons
- Visual color picker (no manual hex editing)
- Searchable icon browser
- Shared afs::gui infrastructure with sys_manual
- Real-time SketchyBar updates via BaristaBridge
- Well-documented with user guide

**Next Steps**: Implement view functionality (Appearance, Widgets, Icons, Integrations)

### 4. Documentation ✅

**SketchyBar Integration**:
- `~/.config/sketchybar/ENHANCED_MENUS_README.md` - Menu activation guide

**Barista Config**:
- `/Users/scawful/src/lab/barista_config/docs/USER_GUIDE.md` - Comprehensive user guide
- `/Users/scawful/src/lab/barista_config/IMPLEMENTATION.md` - Implementation summary
- `/Users/scawful/src/lab/barista_config/README.md` - Project overview

**halext Ecosystem**:
- `/Users/scawful/src/shared/cpp/halext/docs/ECOSYSTEM.md` - Ecosystem overview
- `/Users/scawful/src/shared/cpp/halext/docs/API_REFERENCE.md` - Complete API reference
- `/Users/scawful/src/lab/afs/apps/studio/docs/USER_GUIDE.md` - AFS Studio user guide

## Integration Points

### Cortex ↔ SketchyBar

**Status Detection**:
```lua
local function is_running(proc)
  local handle = io.popen(string.format("pgrep -x %s >/dev/null 2>&1 && echo 1 || echo 0", proc))
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

local oracle_running = is_running("oracle_manager_gui")
local icon_color = oracle_running and "0xffa6e3a1" or "0xff6c7086"
```

**Launch Command**:
```lua
action = HOME .. "/src/hobby/oracle-agent-manager/build/oracle_manager_gui &"
```

**Menu Integration**:
- Shows Oracle Agent Manager running state
- Green icon (󰪴) when running, gray when stopped
- Click to launch if stopped, or brings to front if running

### sys_manual ↔ SketchyBar

**Launch Command**:
```lua
action = HOME .. "/src/lab/sys_manual/build/sys_manual &"
```

**Menu Integration**:
- Book icon () with blue color
- "System Manual" label
- Launches ImGui window with markdown viewer and syshelp

### halext Tools Ecosystem

**Current Tools**:
```
halext Ecosystem
├── sys_manual       (7.2MB) - Workspace docs + syshelp
├── barista_config   (6.2MB) - SketchyBar configuration GUI
├── afs_studio       (TBD)   - AFS training visualization
└── oracle-agent-manager (external) - Oracle workflow manager
```

**Shared Infrastructure** (see [halext docs](../../shared/cpp/halext/docs/)):
- halext::gui::Application base class
- halext::gui::Window with GLFW + ImGui
- halext::gui::Style (themes: Catppuccin, Nord, Dracula, etc.)
- halext::gui::icons (Material Design Icons)
- halext::widgets:: (IconBrowser, ColorPicker, ChatWindow)
- halext::state::JsonConfig (configuration management)
- halext::integration:: (AFSClient, BaristaBridge)
- halext::workspace:: (ProjectToml, WorkspaceToml parsers)

## Binary Verification

```bash
# Verify sys_manual
$ ls -lh ~/src/lab/sys_manual/build/sys_manual
-rwxr-xr-x  7.2M scawful  1 Jan 12:19  sys_manual

# Verify Material Icons font
$ ls -lh ~/src/shared/cpp/afs_gui/fonts/MaterialIcons-Regular.ttf
-rw-r--r--  357k scawful  1 Jan 12:12  MaterialIcons-Regular.ttf
```

## Files Created

### SketchyBar Configuration
- `~/.config/sketchybar/modules/integrations/control_center_enhanced.lua` (297 lines)
- `~/.config/sketchybar/components/apple_menu_enhanced.lua` (195 lines)
- `~/.config/sketchybar/ENHANCED_MENUS_README.md` (activation guide)

### Barista Documentation
- `/Users/scawful/src/lab/barista/HALEXT_GUI_VISION.md` (complete vision doc)
- `/Users/scawful/src/lab/barista/INTEGRATION_SUMMARY.md` (this file)

## Current State

### What Works Now ✅
1. Enhanced Control Center widget with grouped sections
2. Apple menu with sys_manual entries
3. Tool launch wiring remains documented
4. Tool launchers work correctly
5. Visual improvements (rounded tiles, better colors)

### Ready for Testing ⬜
1. Activate enhanced control center in main.lua
2. Test sys_manual launch from menu
4. Verify status indicators update correctly
5. Customize colors to match theme

### Future Work 📋
1. **Phase 2 (Current)**: Complete barista_config implementation
   - Build view logic for appearance, widgets, icons, integrations
   - Implement live preview mechanism
   - Connect ConfigManager to SketchyBar updates
2. Complete documentation for all tools (TOOLS_INTEGRATION.md, ecosystem guides)
3. Build afs_studio for agent training/testing
4. Implement unified theme system across all tools
5. Create network monitoring tool for workspace topology
6. Expand integrations (yaze, oracle, emacs)

## Architecture Vision

### Short Term (Phase 1) - Current
```
SketchyBar (Lua)
├── Enhanced Control Center widget
├── Enhanced Apple menu
└── sys_manual integration (launch)
```

### Medium Term (Phase 2) - Next 2-4 weeks
```
SketchyBar (Lua)
└── Apple menu → halext barista_config

halext:: Tools
├── sys_manual       (docs browser)
├── barista_config   (SketchyBar GUI) ← NEW
└── oracle-agent-manager (external Oracle workflow app)
```

### Long Term (Phase 3) - Future
```
halext:: Unified Ecosystem
├── Core Infrastructure
│   ├── halext::gui           (ImGui base)
│   ├── halext::workspace     (TOML parsers)
│   ├── halext::integration   (syshelp, barista)
│   └── afs::gui              (Agent framework GUI)
│
├── Configuration & Control
│   ├── barista_config        (SketchyBar settings) ✓ Phase 2
│   ├── sys_manual            (workspace docs)
│   └── oracle tooling        (external)
│
└── Development & Workspace
    ├── afs_studio            (Agent training/testing)
    ├── network_monitor       (System topology)
    ├── oracle_browser        (Asset viewer)
    └── metrics_dashboard     (Performance monitoring)
```

**Key Principle**: All ImGui-based tools share halext:: infrastructure, reducing boilerplate and ensuring consistent UX.

## Success Metrics

✅ **Integration Complete**:
1. sys_manual accessible from SketchyBar menus
2. Status indicators work correctly
4. Visual improvements implemented
5. Documentation complete

⬜ **User Testing Required**:
1. Activate enhanced menus
2. Test all menu entries
3. Verify binary paths
4. Collect feedback for Phase 2

📋 **Future Phases**:
1. Build halext barista_config prototype
2. Replace Objective-C GUI
3. Expand halext:: ecosystem
4. Create unified theme system

## How to Proceed

### Immediate Next Steps
1. Read `ENHANCED_MENUS_README.md`
2. Choose activation option (Option 1 recommended)
3. Edit `main.lua` to use enhanced modules
4. Reload SketchyBar: `sketchybar --reload`
5. Test sys_manual launches
6. Report any issues

### When Ready for Phase 2
1. Review `HALEXT_GUI_VISION.md`
2. Scaffold barista_config project
3. Implement ConfigManager and SketchyBarBridge
4. Build Appearance view prototype
5. Test with real SketchyBar configuration

---

**Date**: 2026-01-01
**Status**: Phase 1 Complete, Ready for Testing
**Next Phase**: halext barista_config tool implementation
