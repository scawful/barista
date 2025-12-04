#!/bin/bash
# Barista Health Check Script
# Diagnoses why SketchyBar might not be running

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
SKETCHYBAR_LABEL="homebrew.mxcl.sketchybar"
DOMAIN="gui/$(id -u)"
LABEL="${DOMAIN}/${SKETCHYBAR_LABEL}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

echo "Barista Health Check"
echo "==================="
echo ""

# Check 1: Is SketchyBar process running?
echo "1. Checking SketchyBar process..."
if pgrep -x "sketchybar" > /dev/null; then
    PID=$(pgrep -x "sketchybar")
    print_status "OK" "SketchyBar is running (PID: $PID)"
else
    print_status "FAIL" "SketchyBar process is not running"
fi
echo ""

# Check 2: Launch agent status
echo "2. Checking launch agent status..."
if launchctl print "$LABEL" >/dev/null 2>&1; then
    print_status "OK" "Launch agent is loaded"
    launchctl print "$LABEL" 2>/dev/null | grep -E "(PID|state|LastExitStatus)" || true
else
    print_status "FAIL" "Launch agent is not loaded"
    echo "   Try: launchctl bootstrap $DOMAIN ~/Library/LaunchAgents/${SKETCHYBAR_LABEL}.plist"
fi
echo ""

# Check 3: Launch agent plist exists
echo "3. Checking launch agent plist..."
PLIST="$HOME/Library/LaunchAgents/${SKETCHYBAR_LABEL}.plist"
if [ -f "$PLIST" ]; then
    print_status "OK" "Plist exists: $PLIST"
else
    print_status "WARN" "Plist not found: $PLIST"
    echo "   SketchyBar may be managed by Homebrew services instead"
fi
echo ""

# Check 4: Configuration files
echo "4. Checking configuration files..."
SKETCHYBARRC="$CONFIG_DIR/sketchybarrc"
if [ -f "$SKETCHYBARRC" ]; then
    print_status "OK" "sketchybarrc exists"
    if [ -x "$SKETCHYBARRC" ]; then
        print_status "OK" "sketchybarrc is executable"
    else
        print_status "WARN" "sketchybarrc is not executable (run: chmod +x $SKETCHYBARRC)"
    fi
else
    print_status "FAIL" "sketchybarrc not found: $SKETCHYBARRC"
fi

MAIN_LUA="$CONFIG_DIR/main.lua"
if [ -f "$MAIN_LUA" ]; then
    print_status "OK" "main.lua exists"
else
    print_status "FAIL" "main.lua not found: $MAIN_LUA"
fi

STATE_JSON="$CONFIG_DIR/state.json"
if [ -f "$STATE_JSON" ]; then
    print_status "OK" "state.json exists"
    if python3 -m json.tool "$STATE_JSON" >/dev/null 2>&1; then
        print_status "OK" "state.json is valid JSON"
    else
        print_status "FAIL" "state.json is not valid JSON"
    fi
else
    print_status "WARN" "state.json not found (will be created on first run)"
fi
echo ""

# Check 5: Required binaries
echo "5. Checking required binaries..."
BINARIES=("popup_hover" "popup_anchor" "submenu_hover" "popup_manager" "popup_guard" "menu_action")
for bin in "${BINARIES[@]}"; do
    BIN_PATH="$CONFIG_DIR/bin/$bin"
    if [ -x "$BIN_PATH" ]; then
        print_status "OK" "$bin exists and is executable"
    else
        print_status "WARN" "$bin not found or not executable: $BIN_PATH"
    fi
done
echo ""

# Check 6: Permissions
echo "6. Checking permissions..."
# Check Accessibility permissions (requires tccutil or sqlite3)
if command -v sqlite3 >/dev/null 2>&1; then
    SKETCHYBAR_BUNDLE="com.koekeishiya.sketchybar"
    DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -f "$DB" ]; then
        ACCESS=$(sqlite3 "$DB" "SELECT allowed FROM access WHERE service='kTCCServiceAccessibility' AND client='$SKETCHYBAR_BUNDLE';" 2>/dev/null || echo "0")
        if [ "$ACCESS" = "1" ]; then
            print_status "OK" "Accessibility permission granted"
        else
            print_status "WARN" "Accessibility permission may not be granted"
            echo "   Go to: System Settings > Privacy & Security > Accessibility"
        fi
    else
        print_status "WARN" "Cannot check permissions (TCC.db not accessible)"
    fi
else
    print_status "WARN" "sqlite3 not found, cannot check permissions"
fi
echo ""

# Check 7: Launch agent logs
echo "7. Checking logs..."
if [ -f "/tmp/barista.control.out.log" ]; then
    print_status "OK" "Launch agent stdout log exists"
    echo "   Last 5 lines:"
    tail -n 5 "/tmp/barista.control.out.log" | sed 's/^/   /'
else
    print_status "WARN" "Launch agent stdout log not found"
fi

if [ -f "/tmp/barista.control.err.log" ]; then
    ERR_SIZE=$(stat -f%z "/tmp/barista.control.err.log" 2>/dev/null || echo "0")
    if [ "$ERR_SIZE" -gt 0 ]; then
        print_status "WARN" "Launch agent stderr log has content"
        echo "   Last 5 lines:"
        tail -n 5 "/tmp/barista.control.err.log" | sed 's/^/   /'
    else
        print_status "OK" "Launch agent stderr log is empty"
    fi
fi

SKETCHYBAR_LOG="$HOME/Library/Logs/sketchybar/sketchybar.log"
if [ -f "$SKETCHYBAR_LOG" ]; then
    print_status "OK" "SketchyBar log exists"
    echo "   Last 5 lines:"
    tail -n 5 "$SKETCHYBAR_LOG" | sed 's/^/   /'
fi
echo ""

# Check 8: Dependencies
echo "8. Checking dependencies..."
if command -v yabai >/dev/null 2>&1; then
    print_status "OK" "yabai is installed"
else
    print_status "WARN" "yabai not found (optional)"
fi

if command -v jq >/dev/null 2>&1; then
    print_status "OK" "jq is installed"
else
    print_status "WARN" "jq not found (required for spaces management)"
fi

if command -v lua >/dev/null 2>&1; then
    print_status "OK" "lua is installed"
    LUA_VERSION=$(lua -v 2>&1 | head -n1)
    echo "   $LUA_VERSION"
else
    print_status "FAIL" "lua not found (required)"
fi
echo ""

# Summary and recommendations
echo "Summary"
echo "======="
if ! pgrep -x "sketchybar" > /dev/null; then
    echo ""
    echo "SketchyBar is not running. Try:"
    echo "  1. Start via launch agent:"
    echo "     $CONFIG_DIR/helpers/launch_agent_manager.sh start $SKETCHYBAR_LABEL"
    echo ""
    echo "  2. Or start via Homebrew:"
    echo "     brew services start sketchybar"
    echo ""
    echo "  3. Or reload directly:"
    echo "     sketchybar --reload"
fi

