#!/bin/bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
GUI_DIR="${CONFIG_DIR}/gui"
# Try new unified config_menu first, fallback to old versions
PANEL_BIN="${GUI_DIR}/bin/config_menu"
FALLBACK_BIN="${GUI_DIR}/bin/config_menu_v2"
LOG_FILE="/tmp/sketchybar_config_menu.log"
BUILD_LOG="/tmp/sketchybar_gui_build.log"

launch_panel() {
  # Check if we're in the source directory (for development)
  SOURCE_DIR="${HOME}/Code/barista"
  if [ -x "${SOURCE_DIR}/build/bin/config_menu" ]; then
    "${SOURCE_DIR}/build/bin/config_menu" >"$LOG_FILE" 2>&1 &
    return
  fi
  
  # Use installed binary if available
  if [ -x "$PANEL_BIN" ]; then
    "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
  elif [ -x "$FALLBACK_BIN" ]; then
    "$FALLBACK_BIN" >"$LOG_FILE" 2>&1 &
  else
    osascript -e 'display alert "SketchyBar" message "Control panel not found. Build it with: cd ~/Code/barista && ./rebuild_gui.sh"' >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "--panel" ]; then
  launch_panel
  exit 0
fi

case "${MODIFIER:-}" in
  *shift*)
    launch_panel
    ;;
  *)
    sketchybar -m --set "$NAME" popup.drawing=toggle
    ;;
esac
