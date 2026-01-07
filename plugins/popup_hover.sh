#!/bin/sh

HIGHLIGHT="${POPUP_HOVER_COLOR:-0x40f5c2e7}"
BORDER_COLOR="${POPUP_HOVER_BORDER_COLOR:-0x60cdd6f4}"
BORDER_WIDTH="${POPUP_HOVER_BORDER_WIDTH:-}"
PARENT_FILE="${TMPDIR:-/tmp}/sketchybar_popup_state/active_parent"
mkdir -p "${TMPDIR:-/tmp}/sketchybar_popup_state"

case "$SENDER" in
  "mouse.entered")
    if [ -n "${SUBMENU_PARENT:-}" ]; then
      printf "%s" "$SUBMENU_PARENT" >"$PARENT_FILE"
    fi
    sketchybar --set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    if [ -n "$BORDER_WIDTH" ]; then
      sketchybar --set "$NAME" background.border_width="$BORDER_WIDTH" background.border_color="$BORDER_COLOR"
    fi
    ;;
  "mouse.exited")
    sketchybar --set "$NAME" background.drawing=off background.border_width=0
    ;;
esac
