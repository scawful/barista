#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-music_studio}"

case "${SENDER:-}" in
  "mouse.entered")
    highlight_with_timeout "$NAME" "$(anchor_hover_props)" "$(anchor_idle_props)"
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    ;;
  "mouse.exited.global")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    sketchybar --set "$NAME" popup.drawing=off
    ;;
esac
