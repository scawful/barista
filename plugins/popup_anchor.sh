#!/bin/bash
set -euo pipefail

_d="${0%/*}"
[ -z "$_d" ] && _d="."
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar_popup_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${NAME}.state"
DELAY="${POPUP_CLOSE_DELAY:-0.18}"
OPEN_ON_ENTER="${POPUP_OPEN_ON_ENTER:-0}"

case "${SENDER:-}" in
  "mouse.clicked")
    if [ -n "${NAME:-}" ]; then
      sketchybar --set "$NAME" popup.drawing=toggle
    fi
    ;;
  "mouse.entered")
    hover_token >"$STATE_FILE"
    if [ -n "${NAME:-}" ]; then
      highlight_with_timeout "$NAME" "$(anchor_hover_props)" "$(anchor_idle_props)"
    fi
    if [ "$OPEN_ON_ENTER" = "1" ] && [ -n "${NAME:-}" ]; then
      sketchybar --set "$NAME" popup.drawing=on
    fi
    ;;
  "mouse.exited")
    if [ -n "${NAME:-}" ]; then
      clear_highlight "$NAME" "$(anchor_idle_props)"
    fi
    ;;
  "mouse.exited.global")
    token=""
    if [ -f "$STATE_FILE" ]; then
      IFS= read -r token < "$STATE_FILE" || true
    fi
    if [ -n "${NAME:-}" ]; then
      clear_highlight "$NAME" "$(anchor_idle_props)"
    fi
    (
      sleep "$DELAY"
      current=""
      if [ -f "$STATE_FILE" ]; then
        IFS= read -r current < "$STATE_FILE" || true
      fi
      if [ "$current" = "$token" ] && [ -n "${NAME:-}" ]; then
        # shellcheck disable=SC2046,SC2086
        sketchybar --set "$NAME" popup.drawing=off $(anchor_idle_props)
      fi
    ) &
    ;;
esac
