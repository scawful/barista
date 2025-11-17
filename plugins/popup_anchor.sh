#!/bin/bash
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/sketchybar_popup_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${NAME}.state"
DELAY="${POPUP_CLOSE_DELAY:-0.18}"

case "${SENDER:-}" in
  "mouse.entered")
    date +%s%N >"$STATE_FILE"
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
