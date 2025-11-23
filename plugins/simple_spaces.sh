#!/bin/bash

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
SPACES_CACHE_FILE="${CONFIG_DIR}/.spaces_cache.spaces"

RAW_SPACES_DATA=""
if command -v yabai >/dev/null 2>&1; then
    RAW_SPACES_DATA=$(yabai -m query --spaces 2>/dev/null || echo "")
else
    echo "ERROR: yabai not found." >&2
    exit 1
fi

declare -a SPACE_LINES=()
current_signature=""
if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r line; do
      SPACE_LINES+=("$line")
    done < <(printf '%s\n' "$RAW_SPACES_DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
    current_signature="$(IFS=,; echo "${SPACE_LINES[*]}")"
fi

if [ ${#SPACE_LINES[@]} -eq 0 ]; then
  # Fallback if yabai returns nothing but runs
  for i in {1..10}; do
    SPACE_LINES+=("1 $i")
  done
  current_signature="$(IFS=,; echo "${SPACE_LINES[*]}")"
fi

# Skip rebuild if spaces unchanged
if [ -n "$current_signature" ] && [ -f "$SPACES_CACHE_FILE" ]; then
  cached_signature="$(cat "$SPACES_CACHE_FILE" 2>/dev/null || true)"
  if [ "$current_signature" = "$cached_signature" ]; then
    exit 0
  fi
fi

# Wait for front_app anchor to exist (fast poll, short timeout)
for i in {1..10}; do
  if sketchybar --query front_app >/dev/null 2>&1; then
    break
  fi
  sleep 0.03
done

# Prepare batch command
declare -a SB_ARGS=()

# Remove existing spaces first
sketchybar --remove '/space\..*/' >/dev/null 2>&1 || true
sketchybar --remove '/spaces\..*/' >/dev/null 2>&1 || true

last_item="front_app" # Start anchoring after front_app

for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  space_index="${entry##* }"
  item="space.$space_index"

  icon="$space_index"

  SB_ARGS+=(--add space "$item" left)
  SB_ARGS+=(--set "$item" space="$space_index" \
                          display="$display" \
                          icon="$icon" \
                          icon.padding_left=6 \
                          icon.padding_right=6 \
                          icon.color=0xffcdd6f4 \
                          label="" \
                          label.drawing=off \
                          label.color=0xffa6adc8 \
                          label.padding_left=2 \
                          label.padding_right=2 \
                          background.drawing=off \
                          background.color=0x00000000 \
                          background.corner_radius=8 \
                          background.height=20 \
                          script="$CONFIG_DIR/plugins/space.sh" \
                          click_script="$FOCUS_SCRIPT $space_index")
  SB_ARGS+=(--subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh)
  SB_ARGS+=(--move "$item" after "$last_item")
  
  last_item="$item"
done

# Add space creator button (+ icon)
PRIMARY_DISPLAY=1
if command -v yabai >/dev/null 2>&1; then
    PRIMARY_DISPLAY=$(yabai -m query --displays --display | jq .index 2>/dev/null || echo 1)
fi

SB_ARGS+=(--add item space_creator left)
SB_ARGS+=(--set space_creator \
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
                click_script="$HOME/.config/sketchybar/bin/space_manager create")
SB_ARGS+=(--subscribe space_creator mouse.entered mouse.exited)
SB_ARGS+=(--move space_creator after "$last_item")

# Execute all commands in one single call
sketchybar "${SB_ARGS[@]}"

# Cache current signature to skip redundant rebuilds
if [ -n "$current_signature" ]; then
  printf '%s' "$current_signature" >"$SPACES_CACHE_FILE" 2>/dev/null || true
fi
