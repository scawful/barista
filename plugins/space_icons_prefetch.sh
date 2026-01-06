#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
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

if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

windows_json="$(yabai -m query --windows 2>/dev/null || echo "")"
if [ -z "$windows_json" ]; then
  exit 0
fi

mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || true

printf '%s' "$windows_json" | jq -r '
  sort_by(.space)
  | group_by(.space)
  | map({
      space: .[0].space,
      app: (
        (map(select(.["has-focus"] == true))[0].app) //
        (map(select(.["is-minimized"] == false))[0].app) //
        (.[0].app // "")
      )
    })
  | .[]
  | "\(.space)\t\(.app)"
' | while IFS=$'\t' read -r space app; do
  [ -z "${space:-}" ] || [ -z "${app:-}" ] && continue
  icon=""
  if [ -x "$ICON_SCRIPT" ]; then
    icon="$("$ICON_SCRIPT" "$app")"
  fi
  if [ -n "$icon" ]; then
    printf '%s' "$icon" > "$ICON_CACHE_DIR/$space" 2>/dev/null || true
    sketchybar --set "space.$space" icon="$icon" >/dev/null 2>&1 || true
  fi
done
