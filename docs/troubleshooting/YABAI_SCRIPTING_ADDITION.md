# Yabai Scripting Addition & Space Switching Issues

## The Problem
On macOS Sonoma and Sequoia, users often encounter the following error when trying to switch spaces using `yabai` commands:
```
cannot focus space due to an error with the scripting-addition.
```
This prevents `skhd` shortcuts like `yabai -m space --focus next` from working.

## Barista Behavior
Barista falls back to AppleScript for `space-prev` and `space-next` when the scripting addition is missing. Other space focus commands still require the scripting addition. Run:
```bash
~/.config/sketchybar/scripts/yabai_control.sh doctor
```

## Control Panel Shortcuts
- Debug tab: Run Yabai Doctor, Restart Yabai, Restart Shortcuts
- Advanced tab: Scripts Directory override (if you moved scripts)

## Root Cause
Yabai relies on a **Scripting Addition (SA)** to inject code into the macOS Dock process. This allows it to perform advanced actions like instant space switching, removing animations, and creating spaces.

On newer macOS versions, **System Integrity Protection (SIP)** blocks this injection by default. Additionally, recent versions of Yabai (v6.0+) have removed the `install-sa` command, assuming users will handle the necessary SIP configuration manually.

## Solution 1: The "Safe Mode" Workaround (Applied)
If you do not want to disable SIP, you can use a workaround that relies on standard macOS keyboard events instead of Yabai's internal API.

We have modified your `~/.skhdrc` to use AppleScript for navigation:

```bash
# ~/.skhdrc

# Ctrl + Arrows now simulate the native macOS shortcut
ctrl - left : osascript -e 'tell application "System Events" to key code 123 using control down'
ctrl - right : osascript -e 'tell application "System Events" to key code 124 using control down'
```

**Pros:** Works with SIP enabled.
**Cons:** Includes the standard macOS sliding animation when switching spaces; slower than Yabai's instant switch.

## Solution 2: The Full Fix (Advanced)
To enable full Yabai functionality (instant switching, no animations), you must partially disable SIP and configure the system to allow code injection.

### Steps:
1.  **Turn off FileVault** (Optional but recommended to avoid boot loops during changes).
2.  **Enter Recovery Mode**:
    *   **Apple Silicon (M1/M2/M3):** Shut down. Press and hold Power button until "Loading startup options" appears. Select Options > Continue.
    *   **Intel:** Restart and hold `Command + R`.
3.  **Disable SIP** (Filesystem & Debugging restrictions):
    Open Terminal in Recovery Mode and run:
    ```bash
    csrutil enable --without fs --without debug
    ```
    *Alternatively, `csrutil disable` turns it off completely, but is less secure.*
4.  **Reboot**.
5.  **Configure Boot Arguments** (Apple Silicon only):
    Open Terminal in macOS and run:
    ```bash
    sudo nvram boot-args="-arm64e_preview_abi"
    ```
6.  **Reboot again**.
7.  **Load the Scripting Addition**:
    Add this to your `yabairc` or run manually:
    ```bash
    sudo yabai --load-sa
    ```

## Verifying the Fix
To check if the Scripting Addition is loaded:
```bash
sudo yabai --load-sa
yabai -m space --focus next
```
If successful, the space should switch instantly without animation.
