#!/bin/bash

# Volume Widget Script
# Handles volume updates and hover effects

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

if [ -z "$NAME" ]; then
  NAME="volume"
fi

ICON_OVERRIDE="${BARISTA_ICON_VOLUME:-}"
OK_COLOR="${BARISTA_VOLUME_OK:-0xffa6e3a1}"
WARN_COLOR="${BARISTA_VOLUME_WARN:-0xfff9e2af}"
LOW_COLOR="${BARISTA_VOLUME_LOW:-0xfff38ba8}"
MUTE_COLOR="${BARISTA_VOLUME_MUTE:-0xff89b4fa}"

case "$SENDER" in
  "volume_change")
    VOLUME="$INFO"
    ;;
  "mouse.entered")
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  *)
    # Initial load or other events - get current volume
    VOLUME=$(osascript -e 'output volume of (get volume settings)')
    ;;
esac

# If VOLUME is still empty, get it from system
if [ -z "$VOLUME" ]; then
  VOLUME=$(osascript -e 'output volume of (get volume settings)')
fi

MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null || echo false)

OUTPUT_DEVICE=""
if command -v SwitchAudioSource >/dev/null 2>&1; then
  OUTPUT_DEVICE=$(SwitchAudioSource -c -t output 2>/dev/null || true)
fi

# Set icon based on volume level
if [ "$MUTED" = "true" ] || [ "$VOLUME" -eq 0 ]; then
  ICON="󰖁"
else
  case "$VOLUME" in
    [6-9][0-9]|100) ICON="󰕾"
    ;;
    [3-5][0-9]) ICON="󰖀"
    ;;
    [1-9]|[1-2][0-9]) ICON="󰕿"
    ;;
    *) ICON="󰖁"
  esac
fi

if [ -n "$ICON_OVERRIDE" ]; then
  ICON="$ICON_OVERRIDE"
fi

LABEL="${VOLUME}%"
COLOR="$OK_COLOR"
if [ "$MUTED" = "true" ] || [ "$VOLUME" -eq 0 ]; then
  LABEL="Muted"
  COLOR="$MUTE_COLOR"
elif [ "$VOLUME" -gt 70 ]; then
  COLOR="$OK_COLOR"
elif [ "$VOLUME" -gt 30 ]; then
  COLOR="$WARN_COLOR"
else
  COLOR="$LOW_COLOR"
fi

if [ -n "$OUTPUT_DEVICE" ]; then
  sketchybar --set volume.header label="Output: ${OUTPUT_DEVICE}"
else
  sketchybar --set volume.header label="Volume Controls"
fi

# Update widget
sketchybar --set "$NAME" icon="$ICON" label="$LABEL" icon.color="$COLOR" label.color="$COLOR"
