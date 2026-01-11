#!/bin/sh
# OPTIMIZED: Avoid expensive osascript, use yabai if available
# Updated: Show app name only (icon shown in space widget instead)

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

SPACE_SCRIPT="$HOME/.config/sketchybar/plugins/space.sh"
APP_NAME="${INFO:-}"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu_v2|help_center|icon_browser|sketchybar"

case "${SENDER:-}" in
  mouse.exited.global)
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
  mouse.entered|mouse.exited)
    exit 0
    ;;
esac

# OPTIMIZED: Use yabai (faster) instead of osascript when INFO not available
if [ -z "$APP_NAME" ]; then
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

# Show app name only - icon is shown in the space widget
sketchybar --set "$NAME" icon.drawing=off label="$APP_NAME"
sketchybar --set front_app.header label="App Controls · $APP_NAME" >/dev/null 2>&1 || true

# Trigger space update so it shows the app icon
sketchybar --trigger space_change >/dev/null 2>&1 || true
