#!/bin/sh
set -euo pipefail

# Handle mouse events first
if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# Update label only - preserve icon configuration from main.lua
if [ -z "${NAME:-}" ]; then
  NAME="clock"
fi

sketchybar --set "$NAME" label="$(date '+%a %m/%d %I:%M %p')"
