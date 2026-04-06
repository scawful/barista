#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-triforce}"
TRIFORCE_WIDGET_BIN="${BARISTA_TRIFORCE_WIDGET_BIN:-}"
ACTION="${BARISTA_TRIFORCE_ACTION:-}"

popup_is_open() {
  local query
  query="$(sketchybar --query "$NAME" 2>/dev/null || true)"
  [ -n "$query" ] || return 1
  printf '%s' "$query" | python3 -c 'import json, sys; data = json.load(sys.stdin); raise SystemExit(0 if data.get("popup", {}).get("drawing") == "on" else 1)'
}

handle_click() {
  if popup_is_open; then
    sketchybar --set "$NAME" popup.drawing=off
    return 0
  fi

  sketchybar --set "$NAME" popup.drawing=on
  return 0
}

if [ "$ACTION" = "click" ]; then
  handle_click
  exit 0
fi

case "${SENDER:-}" in
  "mouse.entered")
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    animate_set "$NAME" background.drawing=off
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

if [ -n "$TRIFORCE_WIDGET_BIN" ] && [ -x "$TRIFORCE_WIDGET_BIN" ]; then
  exec "$TRIFORCE_WIDGET_BIN"
fi

exit 0
