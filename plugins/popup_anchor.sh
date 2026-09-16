#!/bin/bash
set -euo pipefail

_d="${0%/*}"
[ -z "$_d" ] && _d="."
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

STATE_DIR="${TMPDIR:-/tmp}/sketchybar_popup_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${NAME}.state"
POPUP_ANCHOR_STATE_FILE="$STATE_FILE"
DELAY="${POPUP_CLOSE_DELAY:-0.18}"
OPEN_ON_ENTER="${POPUP_OPEN_ON_ENTER:-0}"

case "${SENDER:-}" in
  "mouse.clicked")
    if [ -n "${NAME:-}" ]; then
      sketchybar --set "$NAME" popup.drawing=toggle
    fi
    ;;
  "mouse.entered")
    if [ -n "${NAME:-}" ]; then
      hover_props="$(anchor_hover_props)"
      if [ "$OPEN_ON_ENTER" = "1" ]; then
        hover_props="$hover_props popup.drawing=on"
      fi
      highlight_with_timeout "$NAME" "$hover_props" "$(anchor_idle_props)"
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
      hover_acquire_lock "$NAME" 0 || exit 0
      current=""
      if [ -f "$STATE_FILE" ]; then
        IFS= read -r current < "$STATE_FILE" || true
      fi
      if [ -n "$token" ] && [ "$current" = "$token" ] && [ -n "${NAME:-}" ]; then
        # shellcheck disable=SC2046,SC2086
        hover_dispatch --set "$NAME" popup.drawing=off $(anchor_idle_props)
      fi
    ) &
    ;;
esac
