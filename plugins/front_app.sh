#!/bin/bash
# OPTIMIZED: Avoid expensive osascript, use yabai if available
# Updated: Show current app glyph in the bar and full name in the popup

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-front_app}"

if [ -n "${BARISTA_SKETCHYBAR_BIN:-}" ]; then
  sketchybar() {
    "$BARISTA_SKETCHYBAR_BIN" "$@"
  }
fi

APP_NAME="${INFO:-}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-$SCRIPTS_DIR/runtime_context.sh}"
APP_ICON_SCRIPT="${BARISTA_APP_ICON_SCRIPT:-$SCRIPTS_DIR/app_icon.sh}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"

# Barista's own binaries to filter out
BARISTA_APPS="config_menu|config_menu_v2|Barista|BaristaControlPanel|Barista Control Panel|help_center|icon_browser|sketchybar"
FRONT_APP_IDLE_BG="${BARISTA_ANCHOR_IDLE_BG:-0x18313a46}"
FRONT_APP_ICON_COLOR="0xFFcad3f5"
FRONT_APP_IDLE_BORDER_WIDTH="${BARISTA_ANCHOR_IDLE_BORDER_WIDTH:-0}"
FRONT_APP_IDLE_BORDER_COLOR="${BARISTA_ANCHOR_IDLE_BORDER_COLOR:-0x00000000}"
FRONT_APP_ACTION_ROWS="${BARISTA_FRONT_APP_ACTION_ROWS:-1}"
case "$FRONT_APP_ACTION_ROWS" in
  0) ;;
  *) FRONT_APP_ACTION_ROWS=1 ;;
esac
FRONT_APP_IDLE_PROPS="$(anchor_idle_props) icon.color=$FRONT_APP_ICON_COLOR"
FRONT_APP_HOVER_PROPS="$(anchor_hover_props) icon.color=$FRONT_APP_ICON_COLOR"

toggle_front_app_popup() {
  if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
    sketchybar --set front_app.more popup.drawing=off --set "$NAME" popup.drawing=toggle
  else
    sketchybar --set "$NAME" popup.drawing=toggle
  fi
}

close_front_app_popup() {
  if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
    sketchybar --set front_app.more popup.drawing=off --set "$NAME" popup.drawing=off
  else
    sketchybar --set "$NAME" popup.drawing=off
  fi
}

case "${SENDER:-}" in
  mouse.clicked)
    toggle_front_app_popup
    exit 0
    ;;
  mouse.exited.global)
    close_front_app_popup
    clear_highlight "$NAME" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
  mouse.entered)
    highlight_with_timeout "$NAME" "$FRONT_APP_HOVER_PROPS" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
  mouse.exited)
    clear_highlight "$NAME" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
esac

if [ "${BARISTA_FRONT_APP_ACTION:-}" = "click" ]; then
  toggle_front_app_popup
  exit 0
fi

STATE_ICON="󰋽"
STATE_LABEL="No managed window"
LOCATION_LABEL="Space ? · Display ?"
APP_ICON="󰣆"
WINDOW_AVAILABLE="false"
CONTEXT_OUTPUT=""

if [ "${SENDER:-}" = "popup_refresh" ] && [ -x "$RUNTIME_CONTEXT_SCRIPT" ]; then
  CONTEXT_OUTPUT="$("$RUNTIME_CONTEXT_SCRIPT" fresh-front-app 2>/dev/null || true)"
fi

if [ -z "$CONTEXT_OUTPUT" ] && [ -x "$FRONT_APP_CONTEXT_SCRIPT" ]; then
  CONTEXT_OUTPUT="$("$FRONT_APP_CONTEXT_SCRIPT" --app "$APP_NAME" 2>/dev/null || true)"
fi

if [ -n "$CONTEXT_OUTPUT" ]; then
  while IFS=$'\t' read -r key value; do
    case "$key" in
      app_name) APP_NAME="$value" ;;
      state_icon) STATE_ICON="$value" ;;
      state_label) STATE_LABEL="$value" ;;
      location_label) LOCATION_LABEL="$value" ;;
      window_available) WINDOW_AVAILABLE="$value" ;;
    esac
  done <<< "$CONTEXT_OUTPUT"
fi

if [ -z "$APP_NAME" ]; then
  if [ -n "$OSASCRIPT_BIN" ]; then
    APP_NAME=$("$OSASCRIPT_BIN" -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  fi
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

if [ "$WINDOW_AVAILABLE" != "true" ] && [ "$STATE_LABEL" != "No managed window" ]; then
  WINDOW_AVAILABLE="true"
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

FLOAT_ACTION_LABEL="Float Window"
FULLSCREEN_ACTION_LABEL="Enter Fullscreen"
TOPMOST_ACTION_LABEL="Make Topmost"
TILE_PRESET_LABEL="Tile Here"

if [ "$WINDOW_AVAILABLE" != "true" ]; then
  FLOAT_ACTION_LABEL="No Window to Float"
  FULLSCREEN_ACTION_LABEL="No Window to Fullscreen"
  TOPMOST_ACTION_LABEL="No Window to Layer"
  TILE_PRESET_LABEL="No Window to Tile"
else
  case "$STATE_LABEL" in
    *Floating*) FLOAT_ACTION_LABEL="Tile Window" ;;
  esac
  case "$STATE_LABEL" in
    *Fullscreen*) FULLSCREEN_ACTION_LABEL="Exit Fullscreen" ;;
  esac
  case "$STATE_LABEL" in
    *Above*) TOPMOST_ACTION_LABEL="Normal Layer" ;;
  esac
fi

FRONT_APP_UPDATE=(
  "$NAME"
  "icon=$APP_ICON"
  icon.drawing=on
  "icon.color=$FRONT_APP_ICON_COLOR"
  icon.padding_left=8
  icon.padding_right=8
  label=
  label.drawing=off
  background.drawing=on
  "background.color=$FRONT_APP_IDLE_BG"
  "background.border_width=$FRONT_APP_IDLE_BORDER_WIDTH"
  "background.border_color=$FRONT_APP_IDLE_BORDER_COLOR"
  --set front_app.header "label=App · $APP_NAME"
  --set front_app.state "icon=$STATE_ICON" "label=$STATE_LABEL"
  --set front_app.location "label=$LOCATION_LABEL"
)
if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
  FRONT_APP_UPDATE+=(
    --set front_app.window.float "label=$FLOAT_ACTION_LABEL"
    --set front_app.window.fullscreen "label=$FULLSCREEN_ACTION_LABEL"
    --set front_app.window.topmost "label=$TOPMOST_ACTION_LABEL"
    --set front_app.preset.tile_here "label=$TILE_PRESET_LABEL"
  )
fi

animate_set "${FRONT_APP_UPDATE[@]}" >/dev/null 2>&1 || true
