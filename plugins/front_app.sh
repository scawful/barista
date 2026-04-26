#!/bin/bash
# OPTIMIZED: Avoid expensive osascript, use yabai if available
# Updated: Show current app glyph in the bar and full name in the popup

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

APP_NAME="${INFO:-}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
APP_ICON_SCRIPT="${BARISTA_APP_ICON_SCRIPT:-$SCRIPTS_DIR/app_icon.sh}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu|config_menu_v2|Barista|BaristaControlPanel|Barista Control Panel|help_center|icon_browser|sketchybar"
FRONT_APP_IDLE_BG="0x18313a46"
FRONT_APP_HOVER_BG="0x28505a6a"
FRONT_APP_ICON_COLOR="0xFFcad3f5"

case "${SENDER:-}" in
  mouse.exited.global)
    sketchybar --set "$NAME" popup.drawing=off
    clear_highlight "$NAME" "background.drawing=on background.color=$FRONT_APP_IDLE_BG icon.color=$FRONT_APP_ICON_COLOR"
    exit 0
    ;;
  mouse.entered)
    highlight_with_timeout "$NAME" "background.drawing=on background.color=$FRONT_APP_HOVER_BG icon.color=$FRONT_APP_ICON_COLOR" "background.drawing=on background.color=$FRONT_APP_IDLE_BG icon.color=$FRONT_APP_ICON_COLOR"
    exit 0
    ;;
  mouse.exited)
    clear_highlight "$NAME" "background.drawing=on background.color=$FRONT_APP_IDLE_BG icon.color=$FRONT_APP_ICON_COLOR"
    exit 0
    ;;
esac

STATE_ICON="󰋽"
STATE_LABEL="No managed window"
LOCATION_LABEL="Space ? · Display ?"
APP_ICON="󰣆"

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

if [ -x "$APP_ICON_SCRIPT" ]; then
  APP_ICON="$("$APP_ICON_SCRIPT" "$APP_NAME" 2>/dev/null || true)"
fi

if [ -z "$APP_ICON" ]; then
  APP_ICON="󰣆"
fi

animate_set "$NAME" icon="$APP_ICON" icon.drawing=on icon.color="$FRONT_APP_ICON_COLOR" icon.padding_left=8 icon.padding_right=8 label="" label.drawing=off background.drawing=on background.color="$FRONT_APP_IDLE_BG"
sketchybar --set front_app.header label="App · $APP_NAME" >/dev/null 2>&1 || true

sketchybar --set front_app.state \
  icon="$STATE_ICON" \
  label="$STATE_LABEL" >/dev/null 2>&1 || true
sketchybar --set front_app.location \
  label="$LOCATION_LABEL" >/dev/null 2>&1 || true
