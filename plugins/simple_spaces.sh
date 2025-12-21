#!/bin/bash

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
RETRY_FILE="$CONFIG_DIR/.spaces_retry"
MAX_SPACE_QUERY_ATTEMPTS=12
SPACE_QUERY_DELAY=0.08

item_exists() {
  local item="${1:-}"
  [ -n "$item" ] || return 1
  sketchybar --query "$item" >/dev/null 2>&1
}

spaces_payload_valid() {
  local payload="${1:-}"
  [ -n "$payload" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -e 'length > 0' >/dev/null 2>&1
    return $?
  fi
  return 0
}

space_data_has_display() {
  local payload="${1:-}"
  local display="${2:-}"
  [ -n "$payload" ] && [ -n "$display" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$payload" | jq -e --argjson display "$display" 'map(.display) | index($display) != null' >/dev/null 2>&1
}

get_active_display() {
  command -v yabai >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  yabai -m query --displays --display 2>/dev/null | jq -r '.index // empty'
}

get_display_count() {
  if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    yabai -m query --displays 2>/dev/null | jq -r 'length' || true
    return 0
  fi
  if command -v sketchybar >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    sketchybar --query displays 2>/dev/null | jq -r 'length' || true
    return 0
  fi
  return 1
}

get_space_display_count() {
  local payload="${1:-}"
  [ -n "$payload" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$payload" | jq -r 'map(.display) | unique | length' || true
}

schedule_spaces_retry() {
  local now last
  now=$(date +%s)
  last=$(cat "$RETRY_FILE" 2>/dev/null || echo 0)
  if [ $((now - last)) -lt 1 ]; then
    return 0
  fi
  printf '%s' "$now" > "$RETRY_FILE" 2>/dev/null || true
  (
    sleep 0.4
    CONFIG_DIR="$CONFIG_DIR" "$CONFIG_DIR/plugins/refresh_spaces.sh" >/dev/null 2>&1 || true
  ) &
}

RAW_SPACES_DATA=""
if command -v yabai >/dev/null 2>&1; then
    for ((attempt=1; attempt<=MAX_SPACE_QUERY_ATTEMPTS; attempt++)); do
      RAW_SPACES_DATA=$(yabai -m query --spaces 2>/dev/null || true)
      if spaces_payload_valid "$RAW_SPACES_DATA"; then
        break
      fi
      sleep "$SPACE_QUERY_DELAY"
    done
else
    echo "ERROR: yabai not found." >&2
    exit 1
fi

if ! spaces_payload_valid "$RAW_SPACES_DATA"; then
  schedule_spaces_retry
  exit 0
fi
rm -f "$RETRY_FILE" 2>/dev/null || true

fallback_active=0
active_display="$(get_active_display || true)"
if [ -n "$active_display" ] && ! space_data_has_display "$RAW_SPACES_DATA" "$active_display"; then
  fallback_active=1
else
  display_count="$(get_display_count || true)"
  space_display_count="$(get_space_display_count "$RAW_SPACES_DATA" || true)"
  if [ -n "$display_count" ] && [ -n "$space_display_count" ]; then
    if [ "$space_display_count" -lt "$display_count" ]; then
      fallback_active=1
    fi
  fi
fi
if [ "$fallback_active" -eq 1 ]; then
  schedule_spaces_retry
fi

# Wait for front_app anchor to exist (fast poll)
for i in {1..20}; do
  if sketchybar --query front_app >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

declare -a SPACE_LINES=()
if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r line; do
      SPACE_LINES+=("$line")
    done < <(printf '%s\n' "$RAW_SPACES_DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
fi

if [ ${#SPACE_LINES[@]} -eq 0 ]; then
  # Fallback if yabai returns nothing but runs
  for i in {1..10}; do
    SPACE_LINES+=("1 $i")
  done
fi

# Prepare batch command
declare -a SB_ARGS=()

# Remove existing spaces first
sketchybar --remove '/space\..*/' >/dev/null 2>&1 || true
sketchybar --remove '/spaces\..*/' >/dev/null 2>&1 || true

anchor_item="front_app"
needs_front_app_reorder=0
if ! item_exists "$anchor_item"; then
  needs_front_app_reorder=1
  if item_exists "apple_menu"; then
    anchor_item="apple_menu"
  else
    anchor_item=""
  fi
fi
last_item="$anchor_item"
declare -a SPACE_ITEMS=()

for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  space_index="${entry##* }"
  item="space.$space_index"
  space_display="$display"
  if [ "$fallback_active" -eq 1 ]; then
    space_display="active"
  fi

  icon="$space_index"
  if [ -f "$ICON_CACHE_DIR/$space_index" ]; then
    cached_icon="$(cat "$ICON_CACHE_DIR/$space_index" 2>/dev/null || true)"
    if [ -n "$cached_icon" ]; then
      icon="$cached_icon"
    fi
  fi

  SB_ARGS+=(--add space "$item" left)
  SB_ARGS+=(--set "$item" space="$space_index" \
                          display="$space_display" \
                          associated_display="$space_display" \
                          associated_space="$space_index" \
                          ignore_association=off \
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
  SB_ARGS+=(--subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh front_app_switched)
  if [ -n "$last_item" ]; then
    SB_ARGS+=(--move "$item" after "$last_item")
  fi
  
  last_item="$item"
  SPACE_ITEMS+=("$item")
done

# Add space creator button (+ icon)
PRIMARY_DISPLAY=1
if command -v yabai >/dev/null 2>&1; then
    PRIMARY_DISPLAY=$(yabai -m query --displays --display | jq .index 2>/dev/null || echo 1)
fi

SB_ARGS+=(--add item space_creator left)
SB_ARGS+=(--set space_creator \
                display="$([ "$fallback_active" -eq 1 ] && echo active || echo "$PRIMARY_DISPLAY")" \
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
if [ -n "$last_item" ]; then
  SB_ARGS+=(--move space_creator after "$last_item")
fi

# Execute all commands in one single call
sketchybar "${SB_ARGS[@]}"

# If front_app wasn't ready yet, reorder spaces once it appears.
if [ "$needs_front_app_reorder" -eq 1 ]; then
  (
    for i in {1..30}; do
      if item_exists "front_app"; then
        last="front_app"
        for space_item in "${SPACE_ITEMS[@]}"; do
          sketchybar --move "$space_item" after "$last" >/dev/null 2>&1 || true
          last="$space_item"
        done
        sketchybar --move space_creator after "$last" >/dev/null 2>&1 || true
        exit 0
      fi
      sleep 0.05
    done
  ) &
fi

# Prefetch icons for faster startup without blocking bar render
if [ -x "$CONFIG_DIR/plugins/space_icons_prefetch.sh" ]; then
  ("$CONFIG_DIR/plugins/space_icons_prefetch.sh" >/dev/null 2>&1 &)
fi
