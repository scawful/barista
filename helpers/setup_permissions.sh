#!/bin/bash
# Automated permission setup for Barista
# Checks and guides users through macOS permission setup

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo_error "This script is for macOS only"
  exit 1
fi

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║  Barista Permission Setup             ║"
echo "╚═══════════════════════════════════════╝"
echo ""

NEEDS_SETUP=false

# Check Accessibility permissions
check_accessibility() {
  local app="$1"
  local app_path=""
  
  # Find app path
  case "$app" in
    sketchybar)
      app_path=$(brew --prefix sketchybar 2>/dev/null)/bin/sketchybar || \
      app_path=$(which sketchybar 2>/dev/null) || return 1
      ;;
    yabai)
      app_path=$(brew --prefix yabai 2>/dev/null)/bin/yabai || \
      app_path=$(which yabai 2>/dev/null) || return 1
      ;;
    skhd)
      app_path=$(brew --prefix skhd 2>/dev/null)/bin/skhd || \
      app_path=$(which skhd 2>/dev/null) || return 1
      ;;
    *)
      return 1
      ;;
  esac
  
  if [[ -z "$app_path" ]]; then
    return 1
  fi
  
  # Check TCC database (requires sudo or user has granted)
  # This is a best-effort check
  local bundle_id=""
  if [[ "$app" == "sketchybar" ]]; then
    bundle_id="com.felixkratz.sketchybar"
  elif [[ "$app" == "yabai" ]]; then
    bundle_id="com.koekeishiya.yabai"
  elif [[ "$app" == "skhd" ]]; then
    bundle_id="com.koekeishiya.skhd"
  fi
  
  # Try to check (may fail if no permissions to read TCC)
  if command -v sqlite3 &> /dev/null; then
    local db_path="/Library/Application Support/com.apple.TCC/TCC.db"
    if [[ -r "$db_path" ]]; then
      local allowed=$(sqlite3 "$db_path" \
        "SELECT allowed FROM access WHERE service='kTCCServiceAccessibility' AND client='$bundle_id';" 2>/dev/null || echo "0")
      if [[ "$allowed" == "1" ]]; then
        return 0
      fi
    fi
  fi
  
  # Fallback: Check if app can request permissions
  # If we can't verify, assume it needs setup
  return 1
}

# Check Screen Recording (for Yabai)
check_screen_recording() {
  if ! command -v yabai &> /dev/null; then
    return 0  # Yabai not installed, skip
  fi
  
  local bundle_id="com.koekeishiya.yabai"
  
  if command -v sqlite3 &> /dev/null; then
    local db_path="/Library/Application Support/com.apple.TCC/TCC.db"
    if [[ -r "$db_path" ]]; then
      local allowed=$(sqlite3 "$db_path" \
        "SELECT allowed FROM access WHERE service='kTCCServiceScreenRecording' AND client='$bundle_id';" 2>/dev/null || echo "0")
      if [[ "$allowed" == "1" ]]; then
        return 0
      fi
    fi
  fi
  
  return 1
}

# Check each component
echo_info "Checking Accessibility permissions..."

if check_accessibility "sketchybar"; then
  echo_success "SketchyBar has Accessibility permissions"
else
  echo_warning "SketchyBar needs Accessibility permissions"
  NEEDS_SETUP=true
fi

if command -v yabai &> /dev/null; then
  if check_accessibility "yabai"; then
    echo_success "Yabai has Accessibility permissions"
  else
    echo_warning "Yabai needs Accessibility permissions"
    NEEDS_SETUP=true
  fi
  
  if check_screen_recording; then
    echo_success "Yabai has Screen Recording permissions"
  else
    echo_warning "Yabai needs Screen Recording permissions"
    NEEDS_SETUP=true
  fi
else
  echo_info "Yabai not installed (optional)"
fi

if command -v skhd &> /dev/null; then
  if check_accessibility "skhd"; then
    echo_success "skhd has Accessibility permissions"
  else
    echo_warning "skhd needs Accessibility permissions"
    NEEDS_SETUP=true
  fi
else
  echo_info "skhd not installed (optional)"
fi

echo ""

if [[ "$NEEDS_SETUP" == true ]]; then
  echo_warning "Some permissions need to be granted"
  echo ""
  echo "To grant permissions:"
  echo "  1. Open System Settings"
  echo "  2. Go to Privacy & Security"
  echo "  3. Select Accessibility"
  echo "     - Add: SketchyBar"
  echo "     - Add: Yabai (if installed)"
  echo "     - Add: skhd (if installed)"
  echo "  4. If using Yabai, also go to Screen Recording"
  echo "     - Add: Yabai"
  echo ""
  
  read -p "Open System Settings now? [Y/n] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo ""
    echo "After granting permissions, run this script again to verify."
  fi
else
  echo_success "All required permissions are granted!"
fi

echo ""
echo_info "Additional Setup Notes:"
echo ""
echo "Yabai System Integrity Protection (SIP):"
echo "  Yabai requires SIP to be disabled for full functionality."
echo "  This is a security trade-off. To disable:"
echo "  1. Boot into Recovery Mode (Cmd+R on startup)"
echo "  2. Open Terminal"
echo "  3. Run: csrutil disable"
echo "  4. Reboot"
echo ""
echo "  Alternative: Use Yabai in 'simple' mode (limited functionality)"
echo "  See: https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection"
echo ""

