#!/bin/bash
# OPTIMIZED: Avoid expensive osascript, use yabai if available
# Updated: Show app name only (icon shown in space widget instead)

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

APP_NAME="${INFO:-}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu|config_menu_v2|BaristaControlPanel|Barista Control Panel|help_center|icon_browser|sketchybar"

case "${SENDER:-}" in
  mouse.exited.global)
    sketchybar --set "$NAME" popup.drawing=off
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  mouse.entered)
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  mouse.exited)
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
esac

STATE_ICON="󰋽"
STATE_LABEL="No managed window"
LOCATION_LABEL="Space ? · Display ?"

if [ -x "$FRONT_APP_CONTEXT_SCRIPT" ]; then
  while IFS=$'\t' read -r key value; do
    case "$key" in
      app_name) APP_NAME="$value" ;;
      state_icon) STATE_ICON="$value" ;;
      state_label) STATE_LABEL="$value" ;;
      location_label) LOCATION_LABEL="$value" ;;
    esac
  done < <("$FRONT_APP_CONTEXT_SCRIPT" --app "$APP_NAME" 2>/dev/null || true)
fi

if [ -z "$APP_NAME" ]; then
  if [ -n "$OSASCRIPT_BIN" ]; then
    APP_NAME=$("$OSASCRIPT_BIN" -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  fi
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

# Filter out barista's own apps - keep previous app visible
case "$APP_NAME" in
  $BARISTA_APPS)
    exit 0
    ;;
esac

# Show app name only - icon is shown in the space widget
sketchybar --set "$NAME" icon.drawing=off label="$APP_NAME"
sketchybar --set front_app.header label="App · $APP_NAME" >/dev/null 2>&1 || true

sketchybar --set front_app.state \
  icon="$STATE_ICON" \
  label="$STATE_LABEL" >/dev/null 2>&1 || true
sketchybar --set front_app.location \
  label="$LOCATION_LABEL" >/dev/null 2>&1 || true
