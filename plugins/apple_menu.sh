#!/bin/bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
OPEN_PANEL_SCRIPT="${CONFIG_DIR}/bin/open_control_panel.sh"

launch_panel() {
  if [ -x "$OPEN_PANEL_SCRIPT" ]; then
    "$OPEN_PANEL_SCRIPT" --tab appearance
  else
    local message
    message="Control panel launcher missing at ${OPEN_PANEL_SCRIPT}"
    osascript -e "display alert \"SketchyBar\" message \"${message}\"" >/dev/null 2>&1 || true
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
