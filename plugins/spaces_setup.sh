#!/bin/bash

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
STATE_FILE="$CONFIG_DIR/state.json"

space_icons=("" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10")

CUSTOM_ICON_DATA=$(python3 - "$STATE_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}
if not isinstance(data, dict):
    data = {}
space_icons = data.get("space_icons") or {}
if isinstance(space_icons, list) or not isinstance(space_icons, dict):
    space_icons = {}
for idx, glyph in space_icons.items():
    if glyph:
        print(f"{idx}\t{glyph}")
PY
)

get_custom_icon() {
  local target="$1"
  while IFS=$'\t' read -r idx glyph; do
    if [ "$idx" = "$target" ]; then
      printf '%s' "$glyph"
      return
    fi
  done <<EOF
$CUSTOM_ICON_DATA
EOF
}

declare -a SPACE_LINES=()

if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  if DATA=$(yabai -m query --spaces 2>/dev/null); then
    while IFS= read -r line; do
      SPACE_LINES+=("$line")
    done < <(printf '%s\n' "$DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
  fi
fi

if [ ${#SPACE_LINES[@]} -eq 0 ]; then
  FALLBACK_COUNT=${SKETCHYBAR_FALLBACK_SPACES:-10}
  for i in $(seq 1 "$FALLBACK_COUNT"); do
    SPACE_LINES+=("1 $i")
  done
fi

sketchybar --remove '/space\..*/' >/dev/null 2>&1 || true
sketchybar --remove '/spaces\..*/' >/dev/null 2>&1 || true

icon_count=${#space_icons[@]}
icon_idx=0
current_display=""
declare -a bracket_members=()

add_bracket() {
  local display="$1"
  shift
  [ "$#" -eq 0 ] && return
  sketchybar --add bracket "spaces.$display" "$@" \
             --set "spaces.$display" background.drawing=off \
                                      background.color="0x00000000" \
                                      background.corner_radius=0 \
                                      background.height=0
}

for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  space_index="${entry##* }"
  item="space.$space_index"

  icon="${space_icons[$icon_idx]}"
  if [ -z "${icon:-}" ]; then
    icon="$space_index"
  fi
  custom_icon=$(get_custom_icon "$space_index")
  if [ -n "$custom_icon" ]; then
    icon="$custom_icon"
  fi

  sketchybar --add space "$item" left \
             --set "$item" space="$space_index" \
                           icon="$icon" \
                           icon.padding_left=6 \
                           icon.padding_right=6 \
                           icon.color="0xffcdd6f4" \
                           label="" \
                           label.drawing=off \
                           label.color="0xffa6adc8" \
                           label.padding_left=2 \
                           label.padding_right=2 \
                           background.drawing=off \
                           background.color="0x00000000" \
                           background.corner_radius=8 \
                           background.height=20 \
                           script="$CONFIG_DIR/plugins/space.sh" \
                           click_script="$FOCUS_SCRIPT $space_index"
  sketchybar --subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh >/dev/null 2>&1 || true
  icon_idx=$(( (icon_idx + 1) % icon_count ))

  if [ -n "$current_display" ] && [ "$display" != "$current_display" ]; then
    add_bracket "$current_display" "${bracket_members[@]}"
    bracket_members=()
  fi

  current_display="$display"
  bracket_members+=("$item")
done

add_bracket "$current_display" "${bracket_members[@]}"

# Add space creator button (+ icon)
sketchybar --add item space_creator left \
           --set space_creator \
                 icon="󰐕" \
                 icon.color="0x80a6adc8" \
                 icon.padding_left=8 \
                 icon.padding_right=8 \
                 label="" \
                 label.drawing=off \
                 background.drawing=off \
                 background.color="0x00000000" \
                 background.corner_radius=8 \
                 background.height=20 \
                 script="$CONFIG_DIR/plugins/space_creator.sh" \
                 click_script="$HOME/.config/sketchybar/bin/space_manager create" \
           --subscribe space_creator mouse.entered mouse.exited

sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
