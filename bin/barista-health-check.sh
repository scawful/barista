#!/bin/bash
# Barista Health Check Script
# Diagnoses why SketchyBar might not be running

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_JSON="$CONFIG_DIR/state.json"
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

resolve_scripts_dir() {
    local override="${BARISTA_SCRIPTS_DIR:-}"
    if [ -n "$override" ]; then
        echo "$override"
        return 0
    fi

    if command -v jq >/dev/null 2>&1 && [ -f "$STATE_JSON" ]; then
        local state_override
        state_override=$(jq -r '.paths.scripts_dir // .paths.scripts // empty' "$STATE_JSON" 2>/dev/null || true)
        if [ -n "$state_override" ] && [ "$state_override" != "null" ]; then
            echo "$state_override"
            return 0
        fi
    fi

    local config_scripts="$CONFIG_DIR/scripts"
    if [ -x "$config_scripts/yabai_control.sh" ]; then
        echo "$config_scripts"
        return 0
    fi

    local legacy_scripts="$HOME/.config/scripts"
    if [ -x "$legacy_scripts/yabai_control.sh" ]; then
        echo "$legacy_scripts"
        return 0
    fi

    echo "$config_scripts"
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

ICON_MAP="$CONFIG_DIR/icon_map.json"
if [ -f "$ICON_MAP" ]; then
    print_status "OK" "icon_map.json exists"
else
    print_status "WARN" "icon_map.json not found (app icon overrides disabled)"
fi
echo ""

# Check 5: Deploy metadata
echo "5. Checking deploy metadata..."
DEPLOY_META="$CONFIG_DIR/.barista_deploy.json"
if [ -f "$DEPLOY_META" ]; then
    print_status "OK" "Deploy metadata found"
    if command -v jq >/dev/null 2>&1; then
        summary=$(jq -r '"\(.timestamp) | \(.git.branch) \(.git.commit) | dirty=\(.git.dirty)"' "$DEPLOY_META" 2>/dev/null || true)
        if [ -n "$summary" ]; then
            echo "   $summary"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        summary=$(python3 - "$DEPLOY_META" <<'PY' 2>/dev/null || true
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
git = data.get("git", {})
timestamp = data.get("timestamp", "unknown")
branch = git.get("branch", "unknown")
commit = git.get("commit", "unknown")
dirty = git.get("dirty", "unknown")
print(f"{timestamp} | {branch} {commit} | dirty={dirty}")
PY
)
        if [ -n "$summary" ]; then
            echo "   $summary"
        fi
    fi
else
    print_status "WARN" "Deploy metadata not found (run scripts/deploy.sh)"
fi
echo ""

# Check 6: Script paths
echo "6. Checking script paths..."
SCRIPTS_DIR="$(resolve_scripts_dir)"
if [ -d "$SCRIPTS_DIR" ]; then
    print_status "OK" "Scripts directory: $SCRIPTS_DIR"
else
    print_status "WARN" "Scripts directory not found: $SCRIPTS_DIR"
fi

required_scripts=("yabai_control.sh" "toggle_shortcuts.sh")
optional_scripts=(
    "toggle_yabai_shortcuts.sh"
    "runtime_update.sh"
    "set_appearance.sh"
    "widget_toggle.sh"
    "set_widget_color.sh"
    "set_space_icon.sh"
    "set_menu_icon.sh"
    "set_clock_font.sh"
    "toggle_system_info_item.sh"
    "set_app_icon.sh"
    "app_icon.sh"
    "bar_logs.sh"
    "yabai_accessibility_fix.sh"
    "update_external_bar.sh"
    "deploy_info.sh"
)

for script in "${required_scripts[@]}"; do
    path="$SCRIPTS_DIR/$script"
    if [ -x "$path" ]; then
        print_status "OK" "$script is available"
    elif [ -f "$path" ]; then
        print_status "WARN" "$script exists but is not executable"
    else
        print_status "FAIL" "$script not found in $SCRIPTS_DIR"
    fi
done

for script in "${optional_scripts[@]}"; do
    path="$SCRIPTS_DIR/$script"
    if [ -x "$path" ]; then
        print_status "OK" "$script is available"
    elif [ -f "$path" ]; then
        print_status "WARN" "$script exists but is not executable"
    else
        print_status "WARN" "$script not found in $SCRIPTS_DIR"
    fi
done

LEGACY_LINK="$HOME/.config/scripts"
if [ -L "$LEGACY_LINK" ] && [ ! -e "$LEGACY_LINK" ]; then
    print_status "WARN" "Legacy scripts symlink is broken: $LEGACY_LINK"
    echo "   Fix: ln -sfn \"$SCRIPTS_DIR\" \"$LEGACY_LINK\""
fi

if [ -f "$HOME/.skhdrc" ] && grep -q "~/.config/scripts" "$HOME/.skhdrc"; then
    if [ ! -e "$LEGACY_LINK" ]; then
        print_status "WARN" "skhdrc references ~/.config/scripts but it is missing"
        echo "   Update ~/.skhdrc to use $SCRIPTS_DIR"
    fi
fi
echo ""

# Check 7: skhd shortcuts configuration
echo "7. Checking skhd shortcuts configuration..."
SKHD_BIN="$(command -v skhd 2>/dev/null || true)"
SKHD_SHORTCUTS="$HOME/.config/skhd/barista_shortcuts.conf"
SKHD_CONFIG_ENV="${SKHD_CONFIG:-}"
SKHD_CONFIG=""

if [ -n "$SKHD_CONFIG_ENV" ]; then
    SKHD_CONFIG="$SKHD_CONFIG_ENV"
elif [ -f "$HOME/.config/skhd/skhdrc" ]; then
    SKHD_CONFIG="$HOME/.config/skhd/skhdrc"
elif [ -f "$HOME/.skhdrc" ]; then
    SKHD_CONFIG="$HOME/.skhdrc"
else
    SKHD_CONFIG="$HOME/.config/skhd/skhdrc"
fi

if [ -z "$SKHD_BIN" ]; then
    print_status "WARN" "skhd not installed (shortcuts disabled)"
else
    if pgrep -x "skhd" > /dev/null; then
        print_status "OK" "skhd is running"
    else
        print_status "WARN" "skhd is not running"
    fi

    if [ -f "$SKHD_SHORTCUTS" ] && [ -s "$SKHD_SHORTCUTS" ]; then
        print_status "OK" "barista shortcuts file present"
    else
        print_status "WARN" "barista shortcuts file missing: $SKHD_SHORTCUTS"
        echo "   Fix: BARISTA_CONFIG_DIR=$CONFIG_DIR lua $CONFIG_DIR/helpers/generate_shortcuts.lua"
    fi

    if [ -f "$SKHD_CONFIG" ]; then
        if grep -q "barista_shortcuts.conf" "$SKHD_CONFIG"; then
            if grep -Eq '^[[:space:]]*\.load[[:space:]]+"[^"]*barista_shortcuts\.conf"' "$SKHD_CONFIG"; then
                print_status "OK" "skhdrc loads barista shortcuts"
            else
                print_status "WARN" "skhdrc loads barista shortcuts without double quotes"
                echo "   Fix: $SCRIPTS_DIR/yabai_control.sh doctor --fix"
            fi
        else
            print_status "WARN" "skhdrc missing barista .load line"
            echo "   Fix: $SCRIPTS_DIR/yabai_control.sh doctor --fix"
        fi
    else
        print_status "WARN" "skhd config not found: $SKHD_CONFIG"
        echo "   Fix: $SCRIPTS_DIR/yabai_control.sh doctor --fix"
    fi

    SKHD_USER=$(id -un 2>/dev/null || echo "user")
    SKHD_ERR_LOG="/tmp/skhd_${SKHD_USER}.err.log"
    if [ -s "$SKHD_ERR_LOG" ]; then
        print_status "WARN" "skhd error log has content: $SKHD_ERR_LOG"
        echo "   Last 3 lines:"
        tail -n 3 "$SKHD_ERR_LOG" | sed 's/^/   /'
        echo "   Fix: $SCRIPTS_DIR/yabai_control.sh doctor --fix"
    fi
fi
echo ""

# Check 8: Required binaries
echo "8. Checking required binaries..."
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

# Check 9: Permissions
echo "9. Checking permissions..."
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

# Check 10: Launch agent logs
echo "10. Checking logs..."
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

# Check 11: Dependencies
echo "11. Checking dependencies..."
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
