#!/bin/bash
# Thin fallback stub — the compiled C binary (submenu_hover) handles this.
# This script exists only as a fallback for Lua-only mode.

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

HOVER_BG="${SUBMENU_HOVER_BG:-0x80cba6f7}"
IDLE_BG="${SUBMENU_IDLE_BG:-0x00000000}"

case "${SENDER:-}" in
  "mouse.entered")
    sketchybar --set "$NAME" \
      popup.drawing=on \
      background.drawing=on \
      background.color="$HOVER_BG" \
      background.corner_radius=6
    ;;
  "mouse.exited"|"mouse.exited.global")
    sketchybar --set "$NAME" \
      popup.drawing=off \
      background.drawing=off \
      background.color="$IDLE_BG"
    ;;
esac
