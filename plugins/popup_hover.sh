#!/bin/sh

HIGHLIGHT="0x40f5c2e7"
PARENT_FILE="${TMPDIR:-/tmp}/sketchybar_popup_state/active_parent"
mkdir -p "${TMPDIR:-/tmp}/sketchybar_popup_state"

case "$SENDER" in
  "mouse.entered")
    if [ -n "${SUBMENU_PARENT:-}" ]; then
      printf "%s" "$SUBMENU_PARENT" >"$PARENT_FILE"
    fi
    sketchybar --set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    ;;
  "mouse.exited")
    sketchybar --set "$NAME" background.drawing=off
    ;;
esac
