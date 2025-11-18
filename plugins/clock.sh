#!/bin/bash
set -euo pipefail

# Handle mouse events first
if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# Ensure NAME is set
if [ -z "${NAME:-}" ]; then
  NAME="clock"
fi

# Format: "Tue 11/18 02:14 PM"
# Icon: "󰥔" (Clock icon)
TIME_LABEL=$(date '+%a %m/%d %I:%M %p')

sketchybar --set "$NAME" \
  icon="󰥔" \
  label="$TIME_LABEL"
