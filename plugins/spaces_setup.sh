#!/bin/bash

set -euo pipefail
# OPTIMIZED: Removed all debug output for better performance

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
STATE_FILE="$CONFIG_DIR/state.json"
CACHE_FILE="${CONFIG_DIR}/.spaces_cache"
last_item=""

# Wait for anchor item (yabai_status) to exist - reduced iterations
for i in {1..20}; do
  sketchybar --query yabai_status >/dev/null 2>&1 && break
  sleep 0.05
done

# Get current display state for comparison
get_display_state() {
  if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(",")' 2>/dev/null || echo ""
  else
    echo ""
  fi
}

current_display_state=$(get_display_state)
RAW_SPACES_DATA=""
if command -v yabai >/dev/null 2>&1; then
    RAW_SPACES_DATA=$(yabai -m query --spaces 2>/dev/null || echo "")
fi

if [ -f "$CACHE_FILE" ]; then
  cached_state=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
  if [ "$current_display_state" = "$cached_state" ] && [ -n "$current_display_state" ]; then
    # Display state unchanged, check if spaces actually changed
    if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
      current_spaces=$(echo "$RAW_SPACES_DATA" | jq -r '[.[] | "\(.display) \(.index)"] | sort | join(",")' 2>/dev/null || echo "")
      cached_spaces=$(cat "${CACHE_FILE}.spaces" 2>/dev/null || echo "")
      if [ "$current_spaces" = "$cached_spaces" ] && [ -n "$current_spaces" ]; then
        exit 0  # OPTIMIZED: Re-enabled early exit when state unchanged
      fi
      echo "$current_spaces" > "${CACHE_FILE}.spaces" || true
    fi
  fi
fi

# Update display state cache
echo "$current_display_state" > "$CACHE_FILE" || true

space_icons=("" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10")

# Fetch custom icons using high-performance C binary
if [ -x "$CONFIG_DIR/bin/state_manager" ]; then
    CUSTOM_ICON_DATA=$("$CONFIG_DIR/bin/state_manager" get-space-icons)
else
    CUSTOM_ICON_DATA=""
fi

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

if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r line; do
      SPACE_LINES+=("$line")
    done < <(printf '%s\n' "$RAW_SPACES_DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
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
                                      background.height=0 >/dev/null 2>&1
}

for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  space_index="${entry##* }"
  item="space.$space_index"

  # Determine effective anchor item
  current_anchor="yabai_status"
  # Fallback chain for anchoring the first item
  if ! sketchybar --query "$current_anchor" >/dev/null 2>&1; then
      current_anchor="front_app"
      if ! sketchybar --query "$current_anchor" >/dev/null 2>&1; then
          current_anchor="control_center"
      fi
  fi

  # If not the first item, anchor to the previous item created in this loop
  effective_anchor="$current_anchor"
  if [ -n "$last_item" ]; then
      effective_anchor="$last_item"
  fi

  # Check for custom icon from state.json first
  custom_icon=$(get_custom_icon "$space_index")
  if [ -n "$custom_icon" ]; then
    icon="$custom_icon"
  else
    icon="${space_icons[icon_idx]}"
  fi

  # Construct and execute sketchybar command directly
  sketchybar --add space "$item" left \
             --set "$item" space="$space_index" \
                           display="$display" \
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
                           click_script="$FOCUS_SCRIPT $space_index" \
             --subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh >/dev/null 2>&1

  sketchybar --move "$item" after "$effective_anchor" >/dev/null 2>&1

  last_item="$item"
  icon_idx=$(( (icon_idx + 1) % icon_count ))

  if [ -n "$current_display" ] && [ "$display" != "$current_display" ]; then
    add_bracket "$current_display" "${bracket_members[@]}"
    bracket_members=()
  fi

  current_display="$display"
  bracket_members+=("$item")
done

add_bracket "$current_display" "${bracket_members[@]}"

# Cache current spaces state for next comparison
if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  current_spaces=$(yabai -m query --spaces 2>/dev/null | jq -r '[.[] | "\(.display) \(.index)"] | sort | join(",")' 2>/dev/null || echo "")
  echo "$current_spaces" > "${CACHE_FILE}.spaces" || true
fi

# Add space creator button (+ icon)
PRIMARY_DISPLAY=1
if command -v yabai >/dev/null 2>&1; then
    PRIMARY_DISPLAY=$(yabai -m query --displays --display | jq .index 2>/dev/null || echo 1)
fi

sketchybar --add item space_creator left \
           --set space_creator \
                 display="$PRIMARY_DISPLAY" \
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
           --subscribe space_creator mouse.entered mouse.exited >/dev/null 2>&1

sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true