#!/bin/bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
GUI_DIR="${CONFIG_DIR}/gui"
PANEL_BIN="${GUI_DIR}/bin/config_menu"
LOG_FILE="/tmp/sketchybar_config_menu.log"
BUILD_LOG="/tmp/sketchybar_gui_build.log"

launch_panel() {
  if [ ! -x "$PANEL_BIN" ] && [ -d "$GUI_DIR" ]; then
    if ! make -C "$GUI_DIR" >"$BUILD_LOG" 2>&1; then
      osascript -e 'display alert "SketchyBar" message "Control panel build failed. See '"$BUILD_LOG"'"' >/dev/null 2>&1 || true
      return
    fi
  fi
  if [ -x "$PANEL_BIN" ]; then
    "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
  else
    osascript -e 'display alert "SketchyBar" message "Control panel binary missing. Run: make -C ~/.config/sketchybar/gui"' >/dev/null 2>&1 || true
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
