#!/bin/sh
set -euo pipefail

CLOCK_WIDGET_BIN="${CLOCK_WIDGET_BIN:-$HOME/.config/sketchybar/bin/clock_widget}"
if [ -x "$CLOCK_WIDGET_BIN" ]; then
  exec "$CLOCK_WIDGET_BIN"
fi

case "${SENDER:-}" in
  "mouse.exited.global")
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

# Update label only - preserve icon configuration from main.lua
sketchybar --set "$NAME" label="$(date '+%a %m/%d %I:%M %p')"
