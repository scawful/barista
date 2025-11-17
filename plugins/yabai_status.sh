#!/bin/bash

# Modern Yabai Status - Icon-only with subtle colors

set -euo pipefail

YABAI_BIN="${YABAI_BIN:-}"
if [ -z "$YABAI_BIN" ] && command -v yabai >/dev/null 2>&1; then
  YABAI_BIN="$(command -v yabai)"
fi

# Modern color scheme - Catppuccin Mocha, subtle backgrounds
COLOR_BSP="0x60a6e3a1"      # Green with transparency
COLOR_STACK="0x60fab387"    # Peach with transparency
COLOR_FLOAT="0x6094e2d5"    # Sky with transparency
COLOR_ERROR="0x60f38ba8"    # Red with transparency
COLOR_WARNING="0x60f9e2af"  # Yellow with transparency

# Icons
ICON_BSP="󰆾"
ICON_STACK="󰓩"
ICON_FLOAT="󰒄"
ICON_ERROR=""
ICON_WARNING=""

if [ -z "$YABAI_BIN" ]; then
  sketchybar --set "$NAME" \
    icon="$ICON_ERROR" \
    label="" \
    background.color="$COLOR_ERROR"
  exit 0
fi

ERR_LOG="/tmp/yabai_${USER}.err.log"

if ! pgrep -xq yabai; then
  sketchybar --set "$NAME" \
    icon="$ICON_WARNING" \
    label="" \
    background.color="$COLOR_ERROR"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  sketchybar --set "$NAME" \
    icon="$ICON_WARNING" \
    label="" \
    background.color="$COLOR_WARNING"
  exit 0
fi

if ! space_json="$("$YABAI_BIN" -m query --spaces --space 2>/dev/null)"; then
  sketchybar --set "$NAME" \
    icon="$ICON_WARNING" \
    label="" \
    background.color="$COLOR_WARNING"
  exit 0
fi

layout="$(printf '%s' "$space_json" | jq -r '.type // "unknown"')"
is_floating="$(printf '%s' "$space_json" | jq -r '."is-floating" // false')"

# Icon-only display with just layout type
status_icon="$ICON_FLOAT"
status_color="$COLOR_FLOAT"
status_label="FLT"

if [ "$is_floating" = "true" ]; then
  status_icon="$ICON_FLOAT"
  status_color="$COLOR_FLOAT"
  status_label="FLT"
elif [ "$layout" = "bsp" ]; then
  status_icon="$ICON_BSP"
  status_color="$COLOR_BSP"
  status_label="BSP"
elif [ "$layout" = "stack" ]; then
  status_icon="$ICON_STACK"
  status_color="$COLOR_STACK"
  status_label="STK"
fi

# Icon with compact label
sketchybar --set "$NAME" \
  icon="$status_icon" \
  label="$status_label" \
  label.font="SF Mono:Semibold:9" \
  label.color="0xffcdd6f4" \
  label.drawing=on \
  background.color="$status_color"
