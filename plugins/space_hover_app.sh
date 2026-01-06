#!/bin/bash

SPACE_INDEX="${NAME#space.}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-}"

expand_path() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

if [ -z "$SCRIPTS_DIR" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  SCRIPTS_DIR=$(jq -r '.paths.scripts_dir // .paths.scripts // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ "$SCRIPTS_DIR" = "null" ]; then
    SCRIPTS_DIR=""
  fi
fi

if [ -n "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$(expand_path "$SCRIPTS_DIR")"
fi

if [ -z "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$CONFIG_DIR/scripts"
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$HOME/.config/scripts"
fi

ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh"

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
