# Barista Performance & Safety Audit

**Date:** 2026-03-01
**Status:** Major Risks Mitigated (Phases 2-4 complete)
**Scope:** `barista/src`, `barista/helpers`, `barista/plugins`

## Executive Summary
Following the initial audit, a comprehensive performance overhaul was executed in early 2026. The number of process forks on hot paths has been reduced by over **90%** through batching and direct process execution.

## Resolved / Mitigated "Hot Spots"

### 1. Network & System Info (Mitigated)
*   **File:** `helpers/system_info_widget.c`
*   **Update:** Batched 5 separate `system()` calls into a single `sketchybar` invocation.
*   **Result:** Reduced 5 fork+exec cycles to 1 per update interval. Perl-based timeouts remain as safety.

### 2. Space Management (Resolved)
*   **File:** `plugins/simple_spaces.sh`
*   **Update:** Implemented comprehensive batching for both fast-path (diff-update) and full-rebuild paths.
*   **Result:** 
    - Fast path: 40+ forks → 1 fork.
    - Full rebuild: Batched removes, adds, sets, and reorders into single calls.

### 3. Popup & Submenu Execution (Resolved)
*   **File:** `helpers/popup_hover.c`
*   **Update:** Replaced `system()` with `execlp()`.
*   **Result:** Eliminates shell parsing and one fork per hover event. Subsecond latency on popups.

### 4. Yabai Query merging (Resolved)
*   **File:** `plugins/refresh_spaces.sh`
*   **Update:** Merged 3 separate `yabai` queries into 1.
*   **Result:** Reduced IPC round-trips and process forks by 66%.

## Ongoing Lua Integration Improvements
The Lua layer now uses a modular architecture (decomposed from `main.lua`) to improve initialization performance and testability.

*   **File:** `modules/shell_utils.lua`
*   - Introduced `command_available()` and `check_service()` to standardize and optimize external dependency checks.
*   - Lazy-loading of `sketchybar` module to ensure testability and faster startup.

## Remaining Considerations
1.  **Icon Management**: While `icon_manager.c` is stable, further batching of icon updates could be explored if icon-heavy profiles are used.
2.  **Async I/O**: The short-term mitigation (timeouts) is effective, but long-term migration to a fully async event loop remains an architectural target for version 3.0.

## Shell Script Optimization Summary
- **AWK Variable Naming**: Standardized to avoid collisions.
- **Binary Paths**: Fixed to `/opt/homebrew/bin/sketchybar` (or resolved via `paths.lua`).
- **Batching**: System-wide adoption of array-based argument building for `sketchybar` calls.
