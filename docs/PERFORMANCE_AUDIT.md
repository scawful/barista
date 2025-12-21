# Barista Performance & Safety Audit

**Date:** 2025-12-17
**Status:** Critical Risk Identified
**Scope:** `barista/src`, `barista/helpers`

## Executive Summary
A static analysis of the Barista codebase has identified **520+** instances of blocking shell execution calls (`system()`, `popen()`, `exec()`). These calls suspend the main execution thread of the bar or helper process until the external command completes.

**Risk:** If an external command (e.g., `yabai`, `sketchybar`, `curl`) hangs or is slow, the entire Barista UI will freeze.

## Critical "Hot Spots"
These areas are most likely to cause user-visible lag.

### 1. Network & System Info (High Risk)
*   **File:** `helpers/system_info_widget.c`
*   **Offending Code:**
    ```c
    FILE *fp = popen("ifconfig en0 ...", "r");
    FILE *ssid_fp = popen("networksetup -getairportnetwork en0 ...", "r");
    ```
*   **Impact:** `networksetup` is known to block for seconds if the Wi-Fi driver is busy or scanning. This will freeze the system info widget updates.

### 2. Icon Management (Medium Risk)
*   **File:** `helpers/icon_manager.c`
*   **Offending Code:** `system(cmd)` is used extensively to fetch or update icons.
*   **Impact:** If the icon cache logic triggers a heavy shell script, icon loading will stutter.

### 3. Space Management (Medium Risk)
*   **File:** `helpers/space_manager.c`
*   **Offending Code:** `system("sketchybar --trigger space_change ...")`
*   **Impact:** While `sketchybar` IPC is usually fast, a blocking call here means Barista waits for Sketchybar to acknowledge the message before continuing.

## Lua Integration Risks
The Lua layer also relies on blocking I/O:
*   **File:** `modules/integrations/halext.lua`
*   **Code:** `local handle = io.popen(cmd)` (uses `curl` internally).
*   **Impact:** Lua's `io.popen` blocks the Lua VM until the process exits. A slow HTTP request to the Halext server will freeze the entire bar configuration logic for that tick.

## Remediation Plan

### Short Term (Mitigation)
1.  **Timeouts:** Wrap critical shell commands in `timeout -s KILL 1s ...` to prevent infinite hangs.
2.  **Backgrounding:** For "fire and forget" commands, ensure `&` is appended to the command string so `system()` returns immediately (though this doesn't capture output).

### Long Term (Architecture Fix)
1.  **Async IPC:** Replace `popen` with a non-blocking `fork()` + `exec()` + `pipe()` loop, managed by a central event loop (e.g., `libuv` or a custom `select()` loop).
2.  **Lua Async:** Use a Lua library like `luv` or move network requests to a separate "fetcher" process that writes to a file, which the main Lua script simply reads.
