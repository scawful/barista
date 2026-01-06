#!/bin/bash
# control_center.sh - SketchyBar Control Center widget update script
# Shows system status: layout mode, service health, dirty repos

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
NAME="${NAME:-control_center}"

# Check if yabai is running and get layout
get_layout() {
  if ! command -v yabai >/dev/null 2>&1; then
    echo "N/A"
    return
  fi
  local layout
  layout=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.type // "unknown"' 2>/dev/null) || layout="unknown"
  case "$layout" in
    bsp) echo "BSP" ;;
    stack) echo "STK" ;;
    float) echo "FLT" ;;
    *) echo "---" ;;
  esac
}

# Check services
check_services() {
  local yabai_ok=0 skhd_ok=0 bar_ok=0
  pgrep -x yabai >/dev/null 2>&1 && yabai_ok=1
  pgrep -x skhd >/dev/null 2>&1 && skhd_ok=1
  pgrep -x sketchybar >/dev/null 2>&1 && bar_ok=1

  if [[ $yabai_ok -eq 1 && $skhd_ok -eq 1 && $bar_ok -eq 1 ]]; then
    echo "healthy"
  else
    echo "degraded"
  fi
}

# Get dirty repo count
get_dirty_count() {
  local cache_file="$HOME/.workspace/cache/dirty.txt"
  if [[ -f "$cache_file" ]]; then
    wc -l < "$cache_file" | tr -d ' '
  else
    echo "0"
  fi
}

# Main
layout=$(get_layout)
health=$(check_services)
dirty=$(get_dirty_count)

# Icon based on health
if [[ "$health" == "healthy" ]]; then
  ICON="󰕮"
  ICON_COLOR="0xffa6e3a1"  # Green
else
  ICON="󰕯"
  ICON_COLOR="0xfff38ba8"  # Red
fi

# Build label (just layout mode, no dirty count)
LABEL="$layout"

# Update widget
sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$ICON_COLOR" \
  label="$LABEL" \
  label.color="0xffcdd6f4"
