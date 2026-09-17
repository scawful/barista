#!/bin/bash
set -euo pipefail

ITEM_NAME="${1:-}"
POPUP_NAME="${2:-}"
COMMAND="${MENU_ACTION_CMD:-}"

HILITE_COLOR="${MENU_ACTION_HILITE:-0x60cba6f7}"
IDLE_DELAY="${MENU_ACTION_RESET_DELAY:-0.04}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-sketchybar}"

[[ ${#ITEM_NAME} -le 255 && ${#POPUP_NAME} -le 255 && ${#HILITE_COLOR} -le 255 && ${#COMMAND} -le 65535 ]] || exit 64
[[ "$IDLE_DELAY" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || IDLE_DELAY=0.04

sbar_args=(-m)
if [ -n "$ITEM_NAME" ]; then
  sbar_args+=(--set "$ITEM_NAME" background.drawing=on "background.color=$HILITE_COLOR")
fi
if [ -n "$POPUP_NAME" ]; then
  sbar_args+=(--set "$POPUP_NAME" popup.drawing=off)
fi
if [ "${#sbar_args[@]}" -gt 1 ]; then
  "$SKETCHYBAR_BIN" "${sbar_args[@]}" >/dev/null 2>&1 || true
fi

if [ -n "$COMMAND" ]; then
  nohup bash -lc "$COMMAND" >/tmp/sketchybar_menu_action.log 2>&1 &
fi

sleep "$IDLE_DELAY"

if [ -n "$ITEM_NAME" ]; then
  "$SKETCHYBAR_BIN" --set "$ITEM_NAME" background.drawing=off
fi
