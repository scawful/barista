#!/bin/bash

# Updates the space_mode item based on the current Yabai layout

MODE="${1:-""}"

if [ -z "$MODE" ]; then
  # Query Yabai if mode not passed
  if command -v yabai >/dev/null 2>&1; then
    MODE=$(yabai -m query --spaces --space | jq -r '.type')
  else
    MODE="float"
  fi
fi

case "$MODE" in
  bsp)
    ICON="󰆾"
    LABEL="BSP"
    COLOR="0xff89b4fa" # Blue
    ;;
  stack)
    ICON="󰓩"
    LABEL="Stack"
    COLOR="0xfff9e2af" # Yellow
    ;;
  float)
    ICON="󰒄"
    LABEL="Float"
    COLOR="0xffcba6f7" # Mauve
    ;;
  *)
    ICON="?"
    LABEL="$MODE"
    COLOR="0xffbac2de" # Subtext
    ;;
esac

sketchybar --set space_mode \
  icon="$ICON" \
  label="$LABEL" \
  icon.color="$COLOR" \
  label.color="$COLOR"
