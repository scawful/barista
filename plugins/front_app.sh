#!/bin/sh

ICON_SCRIPT="$HOME/.config/scripts/app_icon.sh"
APP_NAME="$INFO"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu_v2|help_center|icon_browser|sketchybar"

if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

if [ "$SENDER" != "front_app_switched" ]; then
  APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

# Filter out barista's own apps - keep previous app visible
if echo "$APP_NAME" | grep -qE "^($BARISTA_APPS)$"; then
  # Don't update if it's one of our own apps
  exit 0
fi

ICON="󰣆"
if [ -x "$ICON_SCRIPT" ]; then
  LOOKUP=$("$ICON_SCRIPT" "$APP_NAME")
  if [ -n "$LOOKUP" ]; then
    ICON="$LOOKUP"
  fi
fi

sketchybar --set "$NAME" icon="$ICON" label="$APP_NAME"
sketchybar --set front_app.menu.header label="App Controls · $APP_NAME" >/dev/null 2>&1 || true
