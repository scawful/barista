# SketchyBar Configuration - Complete Architecture Analysis

This directory contains comprehensive architectural documentation for the SketchyBar status bar configuration system.

## Documentation Files

### 1. **ARCHITECTURE_SUMMARY.txt** (355 lines)
**Quick reference guide with key insights**

Start here for a high-level overview. Contains:
- Summary of all major components analyzed
- Key architecture insights (8 main architectural patterns)
- Critical issues identified with impact assessment
- Synchronization points throughout the system
- Information flow diagrams
- Recommendations for hardening
- Key metrics and statistics

**Best for:** Quick understanding, presentations, identifying issues

---

### 2. **ARCHITECTURE_ANALYSIS.md** (983 lines)
**Deep technical analysis of all systems**

Comprehensive breakdown of every major component. Contains:

**1. Event Flow Architecture**
- SketchyBar event sources (13+ built-in events)
- Event subscription patterns in main.lua
- Yabai signal setup (space lifecycle events)
- Complete event flow chains with examples

**2. Icon System Architecture**
- 4-tier icon resolution chain
- Three icon modules (legacy, modern multi-font, C bridge)
- Space-specific icon storage and resolution
- Icon display update paths (state change vs space refresh)

**3. Space Management System**
- Space lifecycle (creation, update, deletion)
- Space mode system (float, bsp, stack)
- Critical race condition in space setup

**4. Front App System**
- Event flow for front app switching
- App filtering and icon resolution
- Dynamic menu population

**5. Menu System Architecture**
- Menu rendering pipeline and context
- Menu item types and structure
- Submenu hover coordination with state files
- Menu action wrapper behavior

**6. Control Panel (GUI) Architecture**
- ConfigurationManager singleton pattern
- SpacesTab implementation details
- Data flow from GUI → state.json → bar updates

**7. C Components and Bridge System**
- C bridge wrapper pattern
- Component switcher with fallback modes
- Key C helpers (popup_hover, submenu_hover, popup_guard)

**8. Data Flow Synchronization Points**
- State persistence (state.json reads/writes)
- Temporary state files (/tmp coordination)
- Potential race conditions

**9. Identified Issues (6 critical issues)**
- Submenu hover timing race
- Space icon state coherence
- Space mode application timing
- Component switcher silent fallback
- Icon resolution UTF-8 validation
- Popup dismissal race with space change

**10. Information Flows and Dependencies**
- Widget update chains
- Configuration update chains
- Space lifecycle configuration flows

**11-14. Architecture Strengths, Weaknesses, Recommendations, File Summary**

**Best for:** Deep understanding, debugging, architecture changes

---

### 3. **ARCHITECTURE_DIAGRAMS.md** (456 lines)
**ASCII diagrams of system flows and relationships**

Visual representations of complex interactions. Contains:

1. **System Component Overview**
   - High-level component relationships
   - Data flow between major systems

2. **Event Flow: Space Creation**
   - Step-by-step flow from Yabai signal to bar update
   - Shows all scripts involved

3. **Icon Resolution Chain**
   - 4-tier fallback system visualization
   - Priority order at each stage

4. **Space Icon Update: GUI Path**
   - User interaction → configuration → bar update
   - Shows state.json role

5. **Menu System: Submenu Hover Coordination**
   - /tmp file state machine
   - Timing and locking mechanism

6. **Data Synchronization Points**
   - state.json read/write sources
   - /tmp file purposes and lifetime

7. **Temporary File State Machine**
   - Detailed flow of hover state files
   - Timing relationships

8. **Component Switcher Architecture**
   - Mode selection and fallback logic

9. **Configuration Flow Summary**
   - Complete flow from user to bar update
   - Event flows from system to bar

**Best for:** Understanding visual relationships, presentations, teaching

---

## Quick Navigation

### By Topic

**Icon System:**
- ARCHITECTURE_ANALYSIS.md - Section 2
- ARCHITECTURE_DIAGRAMS.md - Section 3

**Space Management:**
- ARCHITECTURE_ANALYSIS.md - Section 3
- ARCHITECTURE_DIAGRAMS.md - Section 2
- ARCHITECTURE_SUMMARY.txt - Topic 4

**Menu System:**
- ARCHITECTURE_ANALYSIS.md - Section 5
- ARCHITECTURE_DIAGRAMS.md - Section 5

**Event System:**
- ARCHITECTURE_ANALYSIS.md - Section 1
- ARCHITECTURE_DIAGRAMS.md - Sections 2, 8, 9

**GUI Configuration:**
- ARCHITECTURE_ANALYSIS.md - Section 6
- ARCHITECTURE_DIAGRAMS.md - Section 4

**Issues & Debugging:**
- ARCHITECTURE_SUMMARY.txt - "CRITICAL ISSUES IDENTIFIED"
- ARCHITECTURE_ANALYSIS.md - Section 9

### By Purpose

**Understanding the system:**
1. Start: ARCHITECTURE_SUMMARY.txt
2. Details: ARCHITECTURE_ANALYSIS.md (skim sections 1-5)
3. Visuals: ARCHITECTURE_DIAGRAMS.md

**Debugging specific issue:**
1. Check: ARCHITECTURE_SUMMARY.txt - "CRITICAL ISSUES"
2. Read: ARCHITECTURE_ANALYSIS.md - Section 9
3. Trace: ARCHITECTURE_DIAGRAMS.md for related flow

**Architectural modification:**
1. Review: ARCHITECTURE_ANALYSIS.md - Full document
2. Trace: ARCHITECTURE_DIAGRAMS.md - Affected flows
3. Check: ARCHITECTURE_SUMMARY.txt - Recommendations

**Performance optimization:**
1. Read: ARCHITECTURE_SUMMARY.txt - "Hybrid C/Lua Architecture"
2. Details: ARCHITECTURE_ANALYSIS.md - Section 7
3. Trace: Component lifetimes and update frequencies

---

## Key Architectural Patterns

### 1. Event-Driven Multi-Tier System
- SketchyBar → Lua → Shell → C → System
- 13+ event sources, 20+ subscriptions
- File-based coordination (state.json, /tmp files)

### 2. 4-Tier Icon Resolution Fallback
1. State (custom user icons)
2. Icon Manager (multi-font support)
3. Legacy Library (backward compatibility)
4. Default/Fallback

### 3. Space Lifecycle Management
- Yabai signals trigger setup
- Per-space scripts for updates
- State synchronization with state.json

### 4. Submenu Hover with File Locks
- /tmp file state machine
- Background process cleanup
- Parent popup guard with lock check

### 5. Persistent Configuration via JSON
- Central state.json file
- Multiple readers/writers
- Python inline scripts for updates

### 6. Hybrid C/Lua Architecture
- C for performance-critical paths
- Lua fallback for compatibility
- Component switcher for runtime selection

---

## Critical Issues Summary

| Issue | Severity | Location | Impact |
|-------|----------|----------|--------|
| Submenu hover timing race | CRITICAL | submenu_hover.c | Premature menu closing |
| Space icon state coherence | HIGH | spaces_setup.sh | Icon inconsistency |
| Space mode timing | HIGH | set_space_mode.sh | Wrong mode displayed |
| Component switcher silent fallback | MEDIUM | component_switcher.lua | Hard to debug |
| Icon validation missing | MEDIUM | config_menu_v2.m | Silent data loss |
| Popup dismissal race | MEDIUM | main.lua | Unclear popup behavior |

---

## Files Analyzed

### Core Files (8 main modules)
- main.lua (811 lines)
- modules/state.lua (328 lines)
- modules/icons.lua (411 lines)
- modules/icon_manager.lua (292 lines)
- modules/menu.lua (444 lines)
- modules/c_bridge.lua (310 lines)
- modules/component_switcher.lua (382 lines)

### Plugin Scripts (6 key scripts)
- plugins/spaces_setup.sh (143 lines)
- plugins/space.sh (207 lines)
- plugins/front_app.sh (37 lines)
- plugins/set_space_mode.sh (81 lines)
- plugins/refresh_spaces.sh (12 lines)
- plugins/menu_action.sh (28 lines)

### C Components (3 critical helpers)
- helpers/popup_hover.c (93 lines)
- helpers/submenu_hover.c (162 lines)
- helpers/popup_guard.c (41 lines)

### GUI
- gui/config_menu_v2.m (1562 lines)

**Total: ~6,900 lines analyzed**

---

## Recommendations

### Immediate (Critical)
1. Fix submenu hover timing race (CLOSE_DELAY + file checks)
2. Add input validation to config_menu_v2.m before saving
3. Add event sequencing guarantee for space_change handlers

### Short-term (High Priority)
4. Implement file locking for state.json writes (flock)
5. Add comprehensive logging to /tmp/sketchybar_debug.log
6. Implement atomic writes (temp file + rename pattern)

### Medium-term (Quality of Life)
7. Add component switcher logging (not silent fallbacks)
8. Implement timeouts on all Yabai queries
9. Add state.json versioning for migrations

### Long-term (Architectural)
10. Replace /tmp file coordination with proper IPC
11. Implement transaction system for atomic state changes
12. Add unit tests for component interactions
13. Graceful degradation on corrupted state.json

---

## Usage Examples

### Finding where icons are resolved:
1. ARCHITECTURE_ANALYSIS.md Section 2.1 - Icon resolution chain
2. ARCHITECTURE_DIAGRAMS.md Section 3 - Visual flow
3. Search main.lua for `icon_for()` function

### Understanding space updates:
1. ARCHITECTURE_SUMMARY.txt Topic 4 - Space lifecycle overview
2. ARCHITECTURE_ANALYSIS.md Section 3 - Detailed breakdown
3. ARCHITECTURE_DIAGRAMS.md Section 2 - Event flow

### Debugging popup issues:
1. ARCHITECTURE_ANALYSIS.md Section 5.4 - Submenu coordination
2. ARCHITECTURE_DIAGRAMS.md Section 5 - State machine
3. ARCHITECTURE_SUMMARY.txt - Critical issue #1

---

## Document Generation

These documents were generated through:
- Static code analysis of 18 key files
- Event flow tracing through Lua subscriptions
- Data flow mapping across components
- Race condition identification
- Architecture pattern recognition

Generated: November 17, 2025
Total lines analyzed: ~6,900
Total documentation: 1,794 lines
