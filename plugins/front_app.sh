#!/bin/sh
# OPTIMIZED: Avoid expensive osascript, use yabai if available

ICON_SCRIPT="$HOME/.config/scripts/app_icon.sh"
APP_NAME="$INFO"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu_v2|help_center|icon_browser|sketchybar"

if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# OPTIMIZED: Use yabai (faster) instead of osascript when INFO not available
if [ -z "$APP_NAME" ] && [ "$SENDER" != "front_app_switched" ]; then
  if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    APP_NAME=$(yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty' 2>/dev/null)
  fi
  # Only fall back to osascript if yabai failed
  if [ -z "$APP_NAME" ]; then
    APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  fi
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

# Filter out barista's own apps - keep previous app visible
case "$APP_NAME" in
  config_menu_v2|help_center|icon_browser|sketchybar)
    exit 0
    ;;
esac

ICON="󰣆"
if [ -x "$ICON_SCRIPT" ]; then
  LOOKUP=$("$ICON_SCRIPT" "$APP_NAME")
  if [ -n "$LOOKUP" ]; then
    ICON="$LOOKUP"
  fi
fi

sketchybar --set "$NAME" icon="$ICON" label="$APP_NAME"
sketchybar --set front_app.menu.header label="App Controls · $APP_NAME" >/dev/null 2>&1 || true
