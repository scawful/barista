#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-triforce}"
TRIFORCE_WIDGET_BIN="${BARISTA_TRIFORCE_WIDGET_BIN:-}"

case "${SENDER:-}" in
  "mouse.entered")
    highlight_with_timeout "$NAME" "$(anchor_hover_props)" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited.global")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

if [ -n "$TRIFORCE_WIDGET_BIN" ] && [ -x "$TRIFORCE_WIDGET_BIN" ]; then
  exec "$TRIFORCE_WIDGET_BIN"
fi

exit 0
