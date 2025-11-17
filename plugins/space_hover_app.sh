#!/bin/bash

SPACE_INDEX="${NAME#space.}"
ICON_SCRIPT="$HOME/.config/scripts/app_icon.sh"

if [ -z "$SPACE_INDEX" ]; then
  exit 0
fi

default_icon="$SPACE_INDEX"

if [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" icon="$default_icon"
  exit 0
fi

if ! command -v yabai >/dev/null 2>&1; then
  exit 0
fi

APP_NAME=$(yabai -m query --windows --space "$SPACE_INDEX" 2>/dev/null | jq -r 'sort_by(.\"stack-index\" // 0) | map(select(.\"is-floating\" == false)) | .[0].app // empty')

if [ -z "$APP_NAME" ]; then
  exit 0
fi

ICON=""
if [ -x "$ICON_SCRIPT" ]; then
  ICON=$("$ICON_SCRIPT" "$APP_NAME")
fi

if [ -z "$ICON" ]; then
  case "$APP_NAME" in
    Terminal|iTerm2) ICON="" ;;
    Firefox) ICON="" ;;
    Code) ICON="" ;;
    Finder) ICON="󰀶" ;;
    Safari) ICON="󰀹" ;;
    Spotify) ICON="" ;;
    Mail) ICON="" ;;
    Messages) ICON="" ;;
    *) ICON="󰣆" ;;
  esac
fi

sketchybar --set "$NAME" icon="$ICON"
