#!/bin/bash

# Space Creator Button - Hover effect and new space creation

HOVER_BG="0x60cba6f7"  # Mauve with transparency
IDLE_BG="0x00000000"   # Transparent
HOVER_ICON_COLOR="0xFFcba6f7"  # Bright mauve
IDLE_ICON_COLOR="0x80a6adc8"   # Dim subtext
ITEM_NAME="${NAME:-space_creator}"

case "${SENDER:-}" in
  "mouse.entered")
    sketchybar --set "$ITEM_NAME" \
      background.drawing=on \
      background.color="$HOVER_BG" \
      icon.color="$HOVER_ICON_COLOR"
    ;;
  "mouse.exited")
    sketchybar --set "$ITEM_NAME" \
      background.drawing=off \
      background.color="$IDLE_BG" \
      icon.color="$IDLE_ICON_COLOR"
    ;;
esac
