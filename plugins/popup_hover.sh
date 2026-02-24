#!/bin/sh

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

BORDER_COLOR="${POPUP_HOVER_BORDER_COLOR:-0x60cdd6f4}"
BORDER_WIDTH="${POPUP_HOVER_BORDER_WIDTH:-}"
PARENT_FILE="${TMPDIR:-/tmp}/sketchybar_popup_state/active_parent"
mkdir -p "${TMPDIR:-/tmp}/sketchybar_popup_state"

case "$SENDER" in
  "mouse.entered")
    if [ -n "${SUBMENU_PARENT:-}" ]; then
      printf "%s" "$SUBMENU_PARENT" >"$PARENT_FILE"
    fi
    if [ -n "$BORDER_WIDTH" ]; then
      animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT" background.border_width="$BORDER_WIDTH" background.border_color="$BORDER_COLOR"
    else
      animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    fi
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off background.border_width=0
    ;;
esac
