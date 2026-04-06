#!/bin/bash
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/sketchybar_popup_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${NAME}.state"
DELAY="${POPUP_CLOSE_DELAY:-0.18}"
OPEN_ON_ENTER="${POPUP_OPEN_ON_ENTER:-0}"

case "${SENDER:-}" in
  "mouse.entered")
    date +%s%N >"$STATE_FILE"
    if [ "$OPEN_ON_ENTER" = "1" ] && [ -n "${NAME:-}" ]; then
      sketchybar --set "$NAME" popup.drawing=on
    fi
    ;;
  "mouse.exited.global")
    token=""
    if [ -f "$STATE_FILE" ]; then
      token=$(cat "$STATE_FILE")
    fi
    (
      sleep "$DELAY"
      current=""
      if [ -f "$STATE_FILE" ]; then
        current=$(cat "$STATE_FILE")
      fi
      if [ "$current" = "$token" ] && [ -n "${NAME:-}" ]; then
        sketchybar --set "$NAME" popup.drawing=off
      fi
    ) &
    ;;
esac
