#!/bin/bash
set -euo pipefail

# Clock Widget Script
# Handles time updates and hover effects

if [ -z "${NAME:-}" ]; then
  NAME="clock"
fi

HIGHLIGHT="0x40f5c2e7"

case "${SENDER:-}" in
  "mouse.entered")
    sketchybar --set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    sketchybar --set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

# Format: "Tue 11/18 02:14 PM"
# Icon: "󰥔" (Clock icon)
TIME_LABEL=$(date '+%a %m/%d %I:%M %p')

sketchybar --set "$NAME" \
  icon="󰥔" \
  label="$TIME_LABEL"
