#!/bin/bash
set -euo pipefail

# Clock Widget Script
# Handles time updates and hover effects

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

if [ -z "${NAME:-}" ]; then
  NAME="clock"
fi

case "${SENDER:-}" in
  "mouse.entered")
    highlight_with_timeout "$NAME" "background.drawing=on background.color=$HIGHLIGHT" "background.drawing=off"
    exit 0
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set "$NAME" popup.drawing=off
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
esac

# Format: "Tue 11/18 02:14 PM"
# Icon: "󰥔" (Clock icon)
TIME_LABEL=$(date '+%a %m/%d %I:%M %p')

sketchybar --set "$NAME" label="$TIME_LABEL"
