#!/bin/bash

# Volume Widget Script
# Handles volume updates and hover effects

if [ -z "$NAME" ]; then
  NAME="volume"
fi

HIGHLIGHT="0x40f5c2e7"

case "$SENDER" in
  "volume_change")
    VOLUME="$INFO"

    if [ -z "$VOLUME" ]; then
      VOLUME=$(osascript -e 'output volume of (get volume settings)')
    fi

    case "$VOLUME" in
      [6-9][0-9]|100) ICON="󰕾"
      ;;
      [3-5][0-9]) ICON="󰖀"
      ;;
      [1-9]|[1-2][0-9]) ICON="󰕿"
      ;;
      *) ICON="󰖁"
    esac

    sketchybar --set "$NAME" icon="$ICON" label="$VOLUME%"
    ;;
  "mouse.entered")
    sketchybar --set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    ;;
  "mouse.exited")
    sketchybar --set "$NAME" background.drawing=off
    ;;
esac
