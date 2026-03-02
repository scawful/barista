# SketchyBar Configuration Changelog

## March 1, 2026 - Performance Overhaul & Regression Testing

### 🏗️ Architecture: main.lua Decomposition (Phase 1)

Decomposed the monolithic `main.lua` (751 → 280 lines) into focused modules:

| Module | Responsibility |
|:---|:---|
| `modules/shell_utils.lua` | Shell quoting, exec, file_exists, env_prefix, command_available, check_service |
| `modules/paths.lua` | Path expansion, resolution, table builders |
| `modules/binary_resolver.lua` | Compiled script lookup, window manager mode normalization |
| `modules/submenu_registry.lua` | Dynamic popup/submenu list writing to TMPDIR |

- Unified `menu_context` + `item_ctx` into single `barista_context`
- Removed 3 deprecated GUI files (172KB): `config_menu.m.bak`, `config_menu_v2.m`, `config_menu_enhanced.m`

### ⚡ Performance Improvements (Phases 2 & 4)

#### Space Switching — Batched Fast Path
`plugins/simple_spaces.sh` diff-update fast path batched from N×7 individual `sketchybar --set` forks into a single call.

| Path | Before | After |
|:---|:---|:---|
| Diff-update (fast path) | 40 forks (5 spaces) | **1 fork** |
| Full-rebuild removes | 4 forks | **1 fork** |
| Full-rebuild triggers | 2 forks | **1 fork** |
| Reorder moves | N forks | **1 fork** |

#### Yabai Query Merge
`plugins/refresh_spaces.sh` merged 3 separate `yabai -m query` calls into 1, deriving display/space/active state via jq from the same payload.

#### Popup & Submenu Performance
- `helpers/popup_hover.c`: Replaced `system()` with `execlp()` — saves one fork+exec per hover event
- `helpers/submenu_hover.c` and `helpers/popup_manager.c`: Now read item lists from `$TMPDIR/sketchybar_submenu_list` and `$TMPDIR/sketchybar_popup_list` at startup (written by `submenu_registry.lua`), with hardcoded fallback for backward compatibility
- Shell fallback scripts (`submenu_hover.sh`, `popup_manager.sh`) replaced with thin stubs

#### System Info Widget
`helpers/system_info_widget.c`: Merged 5 separate `system()` calls into a single batched sketchybar invocation, reducing 5 fork+exec cycles to 1 per update interval.

### 🧪 Regression Test Suite (94 Tests)

New lightweight Lua test runner (`tests/run_tests.lua`) with zero external dependencies.

| Test File | Tests | Coverage |
|:---|:---|:---|
| `test_shell_utils.lua` | 22 | Quoting, env_prefix, file_exists, command_available, check_service |
| `test_binary_resolver.lua` | 19 | WM mode normalization (11), enabled computation (6), compiled_script (2) |
| `test_profile.lua` | 15 | Merge precedence, profile selection, integration flags, menu sections |
| `test_paths.lua` | 10 | Path expansion, code_dir resolution, table builders |
| `test_control_center.lua` | 9 | Widget creation, position, popup config, label visibility |
| `test_theme.lua` | 7 | Override merging, nil safety, passthrough |
| `test_state.lua` | 6 | get, get_icon, get_integration with mock state |
| `test_submenu_registry.lua` | 6 | File creation, line format, nil handling |

Smoke test: `scripts/barista-verify.sh` validates tests, binaries, JSON config, modules, and optionally shellcheck.

```bash
lua tests/run_tests.lua              # Unit tests only
./scripts/barista-verify.sh          # Full smoke test
./scripts/barista-verify.sh --quick  # Skip shellcheck
```

### 🔧 Build & Deploy Modernization (Phase 3)

- **CMakePresets.json**: Added `dev` preset with AddressSanitizer for catching memory bugs
- **CMakeLists.txt**: Added post-build `sync_binaries` target — `build/bin/` automatically copies to `bin/` after each build
- **rebuild.sh**: Added `--verify` flag (runs barista-verify.sh after build) and `--preset <name>` flag
- **deploy.sh**: Replaced 33-line inline Python heredoc with 15 lines of `jq` — eliminates Python dependency

### 🧹 Code Quality (Phase 3)

- **control_center.lua**: Replaced 6 duplicated utility functions (`path_exists`, `shell_quote`, `expand_path`, `command_available`, `normalize_mode`, `resolve_scripts_dir`) with `require()` calls to Phase 1 modules (~100 lines removed)
- **shell_utils.lua**: Made testable outside SketchyBar runtime via lazy-loading `sketchybar` C module
- **state.json**: Pretty-printed for readability and git diffs

### 📝 Git History (8 Commits)

```
03ccbc2 perf: batch system_info_widget updates into single sketchybar call
bf57744 perf: batch full-rebuild removes, triggers, and reorder moves
a500ac2 build: add CMake presets, post-build sync, modernize deploy/rebuild
95d1ea3 refactor: dedup control_center.lua, slim shell fallback scripts
a386374 test: add Lua test suite with 94 tests and barista-verify.sh
ae35ff6 perf: batch space switching, merge yabai queries, dynamic submenu discovery
0f039bb chore: remove deprecated GUI code and clean build targets
1835768 refactor: decompose main.lua into shell_utils, paths, binary_resolver modules
```

---

## November 17, 2025 - Critical Fixes & Architecture Documentation

### 🔴 Critical Fixes Applied

#### 1. Apple Menu Icon Not Displaying
**Problem:** Icon showed as empty/blank regardless of configuration
**Root Cause:** Complex c_bridge icon resolution with timing issues + conflicting post-init override
**Solution:**
- Simplified to direct glyph assignment: `icon = "󰀵"`
- Removed c_bridge.icons.get() call (main.lua:335)
- Removed conflicting post-init override (main.lua:803-808)
**Result:** ✅ Icon now displays reliably on all reloads

#### 2. Spaces Tab Crashing Control Panel
**Problem:** Clicking Spaces tab in config_menu_v2 caused immediate crash
**Root Cause:** Missing null checks when accessing state.space_icons/space_modes
**Solution:**
- Added validation for config manager and state (gui/config_menu_v2.m:755-761)
- Auto-create missing dictionaries (lines 764-771)
- Graceful fallback to defaults
**Result:** ✅ Spaces tab loads without crashing

#### 3. Space Icons Flickering (Numbers ↔ Icons)
**Problem:** Space icons would switch between "1", "2", "3" and actual icons
**Root Cause:** Race condition - spaces_setup.sh cycled through icon array before state.json loaded
**Solution:**
- Prioritize state.json lookup first (plugins/spaces_setup.sh:86-92)
- Use space number as static fallback (not cycling array)
- Removed icon_idx cycling logic
**Result:** ✅ Consistent icons across all reloads

#### 4. Volume Widget Broken
**Problem:** Volume widget background color was 0x0 (black/invisible)
**Root Cause:** widget_colors was an array [] instead of object {} in state.json
**Solution:**
- Fixed data structure in state.json
- widget_colors now correctly resolves to theme.volume (0x8020b2aa)
**Result:** ✅ Volume widget displays with correct theme color

---

### 📚 Architecture Documentation (6 New Files)

#### ARCHITECTURE_ANALYSIS.md (983 lines)
**Purpose:** Complete technical deep-dive into system architecture

**Contents:**
- 14 major component sections
- Event flow analysis (13+ event sources)
- Data flow patterns (file-based synchronization)
- Race condition identification (6 critical timing issues)
- Performance analysis (4,900+ LOC analyzed)
- Code references with exact line numbers

**Key Findings:**
- Event-driven multi-tier architecture
- File-based state sync introduces race conditions
- Submenu hover background process cleanup bug
- Space mode async commands without synchronization
- Icon validation missing (silent data loss possible)

#### ARCHITECTURE_DIAGRAMS.md (456 lines)
**Purpose:** Visual maps of system flows

**Contents:**
- 9 ASCII diagrams
- Event flow: SketchyBar → Lua → Shell → C
- State flow: JSON file → Lua → SketchyBar
- Space creation flow with timing
- Icon resolution fallback chain
- Submenu hover state machine
- Front app update flow
- Control panel integration

#### ARCHITECTURE_README.md
**Purpose:** Master navigation guide

**Contents:**
- Quick lookup table by topic
- Documentation index (architecture/guides/troubleshooting/api)
- Critical issues summary with severity
- Recommendations prioritized by urgency

#### ARCHITECTURE_SUMMARY.txt (355 lines)
**Purpose:** Quick reference for developers

**Contents:**
- 8 key architectural patterns
- 6 critical issues with severity levels (CRITICAL/HIGH/MEDIUM)
- Component communication flows
- File system dependencies
- Actionable recommendations

#### docs/ICON_REFERENCE.md (Complete Icon Guide)
**Purpose:** Comprehensive icon system documentation

**Contents:**
- **214 icons** organized into 9 categories:
  - System (32): Apple, settings, power, notifications
  - Hardware (24): Battery, WiFi, volume, CPU, memory
  - Time & Calendar (12): Clock, calendar, timer, schedule
  - Window Management (18): BSP, stack, float, fullscreen
  - Development (32): Terminal, VSCode, Git, Docker
  - Applications (48): Finder, Safari, Chrome, Spotify
  - Files & Folders (16): Folder, document, save, download
  - Gaming (12): Gamepad, triforce, achievements
  - Arrows & Navigation (20): Chevrons, carets, angles

**Features:**
- Icon name → glyph → unicode reference table
- Usage examples for Lua, state.json, control panel
- Icon resolution flow diagram
- Troubleshooting guide (font issues, display problems)
- Best practices (semantic naming, fallbacks, performance)
- Adding new icons (3 methods documented)

#### docs/SYSTEM_FIXES.md
**Purpose:** Implementation guide for remaining issues

**Contents:**
- Root cause analysis for 6 issues
- 3-phase implementation plan:
  - Phase 1: Critical (DONE - Apple icon, spaces crash, icon flickering)
  - Phase 2: Performance (batch space creation, caching)
  - Phase 3: Quality of life (submenu hover, front app C widget)
- Testing procedures
- Rollback plan
- Code snippets for each fix

---

### 🔧 Code Changes Summary

#### main.lua
**Line 335:** Simplified apple menu icon
```lua
-- BEFORE:
icon = c_bridge.icons.get("apple", icon_for("apple", "")),

-- AFTER:
icon = "󰀵",  -- Simple menu icon that works
```

**Lines 803-808:** Removed conflicting override
```lua
-- DELETED:
local apple_icon_value = state_module.get_icon(state, "apple")
if apple_icon_value and apple_icon_value ~= "" then
  sbar.exec(string.format("sketchybar --set apple_menu icon='%s'", apple_icon_value))
end
```

#### gui/config_menu_v2.m
**Lines 751-790:** Added defensive checks in loadSpaceSettings
```objc
// Added validation
if (!config || !config.state) {
    NSLog(@"Config manager or state not initialized");
    // ... set defaults and return
}

// Auto-create missing dictionaries
if (!config.state[@"space_icons"]) {
    config.state[@"space_icons"] = [NSMutableDictionary dictionary];
}
```

#### plugins/spaces_setup.sh
**Lines 85-92:** Fixed icon assignment logic
```bash
# BEFORE: Cycled through icon array, caused flickering
icon="${space_icons[$icon_idx]}"
custom_icon=$(get_custom_icon "$space_index")
if [ -n "$custom_icon" ]; then icon="$custom_icon"; fi

# AFTER: Prioritize state.json, static fallback
custom_icon=$(get_custom_icon "$space_index")
if [ -n "$custom_icon" ]; then
    icon="$custom_icon"
else
    icon="$space_index"  # Use number, not cycling array
fi
```

---

### 📊 Impact Analysis

#### Before Fixes
- ❌ Apple menu icon: Empty/blank
- ❌ Spaces tab: Crash on click
- ❌ Space icons: Flickering (1→→2→→3→)
- ❌ Volume widget: Invisible (0x0 background)
- ❌ Documentation: Scattered across root directory

#### After Fixes
- ✅ Apple menu icon: Displays reliably (󰀵)
- ✅ Spaces tab: Loads without crash
- ✅ Space icons: Consistent across reloads
- ✅ Volume widget: Proper theme color (0x8020b2aa)
- ✅ Documentation: Organized in docs/ and root architecture files

---

### 🚀 Performance & Reliability

#### Eliminated Race Conditions
1. Icon resolution timing (apple menu)
2. State initialization (spaces tab)
3. Icon cycling vs state loading (space icons)
4. Widget color data structure (volume widget)

#### Improved Code Quality
- Added null safety checks (config panel)
- Simplified icon assignment (removed unnecessary abstraction)
- Fixed data structure inconsistencies (state.json)
- Better error handling (graceful fallbacks)

---

### 📖 Documentation Organization

#### Root Directory
- `ARCHITECTURE_ANALYSIS.md` - Technical deep-dive
- `ARCHITECTURE_DIAGRAMS.md` - Visual system maps
- `ARCHITECTURE_README.md` - Master index
- `ARCHITECTURE_SUMMARY.txt` - Quick reference

#### docs/ Directory
```
docs/
├── INDEX.md                    # Main docs index (existing)
├── ICON_REFERENCE.md          # Complete icon guide (NEW)
├── SYSTEM_FIXES.md            # Fix implementation guide (NEW)
├── CHANGELOG.md               # This file (NEW)
├── architecture/              # Existing architecture docs
├── guides/                    # Existing user guides
└── troubleshooting/           # Existing troubleshooting
```

---

### 🔮 Remaining Issues (Phase 2 & 3)

#### Phase 2: Performance Improvements (Not Critical)
1. **Space loading lag** - Batch space creation instead of individual commands
2. **Front app widget refresh** - Create C widget to eliminate shell overhead
3. **Space data caching** - Cache yabai queries (5-second TTL)

#### Phase 3: Quality of Life (Low Priority)
1. **Submenu hover behavior** - Fix background process cleanup timing
2. **Icon gallery in control panel** - Visual icon browser (partially exists)
3. **Front app polling** - Increase update frequency from event-only to 1 second

**Documentation:** See `docs/SYSTEM_FIXES.md` for implementation details

---

### ✅ Testing Performed

#### Manual Testing
1. ✅ Reload SketchyBar multiple times
2. ✅ Verify apple menu icon displays
3. ✅ Open config panel, navigate to Spaces tab
4. ✅ Switch between spaces (1→2→3→1)
5. ✅ Check volume widget background color
6. ✅ Verify space icons don't flicker

#### Automated Validation
```bash
# Icon verification
sketchybar --query apple_menu | grep "value.*udb80"  # ✅ Pass

# Volume widget color
sketchybar --query volume | grep "0x8020b2aa"  # ✅ Pass

# Config panel (no crash test)
~/.config/sketchybar/gui/bin/config_menu_v2  # ✅ Pass
```

---

### 📝 Git Commits

#### Commit: e265be1
**Title:** fix: Critical system fixes and comprehensive architecture documentation

**Files Changed:** 9 files, +3079 lines, -15 lines
- `main.lua` - Apple icon fix, removed override
- `gui/config_menu_v2.m` - Spaces tab crash fix
- `plugins/spaces_setup.sh` - Icon flickering fix
- `ARCHITECTURE_ANALYSIS.md` - NEW
- `ARCHITECTURE_DIAGRAMS.md` - NEW
- `ARCHITECTURE_README.md` - NEW
- `ARCHITECTURE_SUMMARY.txt` - NEW
- `docs/ICON_REFERENCE.md` - NEW
- `docs/SYSTEM_FIXES.md` - NEW

---

### 🎯 Success Metrics

| Metric | Before | After | Status |
|--------|--------|-------|--------|
| Apple icon displays | ❌ No | ✅ Yes | **Fixed** |
| Spaces tab usable | ❌ Crash | ✅ Works | **Fixed** |
| Space icons consistent | ❌ Flicker | ✅ Stable | **Fixed** |
| Volume widget visible | ❌ Invisible | ✅ Visible | **Fixed** |
| Documentation organized | ❌ Scattered | ✅ Structured | **Improved** |
| Architecture documented | ❌ None | ✅ Complete | **Added** |
| Icon reference available | ❌ None | ✅ 214 icons | **Added** |

---

### 🔄 Future Work

See `docs/SYSTEM_FIXES.md` for:
- Phase 2 performance improvements
- Phase 3 quality of life enhancements
- Testing procedures for each fix
- Rollback plans if issues arise

---

**Date:** November 17, 2025
**Version:** 2.0
**Status:** ✅ Critical fixes complete, system stable
**Next:** Phase 2 performance improvements (optional)
