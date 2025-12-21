#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
ICON_SCRIPT="$HOME/.config/scripts/app_icon.sh"

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
