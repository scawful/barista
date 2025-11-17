#!/bin/bash
set -euo pipefail

ITEM_NAME="${1:-}"
POPUP_NAME="${2:-}"
COMMAND="${MENU_ACTION_CMD:-}"

HILITE_COLOR="0x60cba6f7"
IDLE_DELAY=0.18

if [ -n "$ITEM_NAME" ]; then
  sketchybar --set "$ITEM_NAME" background.drawing=on background.color="$HILITE_COLOR"
fi

if [ -n "$COMMAND" ]; then
  nohup bash -lc "$COMMAND" >/tmp/sketchybar_menu_action.log 2>&1 &
fi

if [ -n "$POPUP_NAME" ]; then
  sketchybar -m --set "$POPUP_NAME" popup.drawing=off >/dev/null 2>&1 || true
fi

sleep "$IDLE_DELAY"

if [ -n "$ITEM_NAME" ]; then
  sketchybar --set "$ITEM_NAME" background.drawing=off
fi
