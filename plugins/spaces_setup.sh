#!/bin/bash

set -euo pipefail
# set -x # Uncomment for more verbose debugging

START_TIME=$SECONDS
DEBUG_SPACES="${SPACES_DEBUG:-0}"
FORCE_REFRESH="${SPACES_FORCE_REFRESH:-0}"

log_debug() {
  [ "$DEBUG_SPACES" = "0" ] && return
  echo "$@" >&2
}

log_debug "--- Starting spaces_setup.sh (final rewrite, no helper) at $(date) ---"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
STATE_FILE="$CONFIG_DIR/state.json"
CACHE_FILE="${CONFIG_DIR}/.spaces_cache"
last_item=""

# Wait for anchor item (yabai_status) to exist
log_debug "Waiting for yabai_status..."
for i in {1..50}; do
  if sketchybar --query yabai_status >/dev/null 2>&1; then
    log_debug "yabai_status found."
    break
  fi
  sleep 0.1
done

# Get current display state for comparison
get_display_state() {
  if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(",")' 2>/dev/null || echo ""
  else
    echo "" >&2
  fi
}

log_debug "Calling get_display_state..."
current_display_state=$(get_display_state)
log_debug "Current display state: $current_display_state"
RAW_SPACES_DATA=""
if command -v yabai >/dev/null 2>&1; then
    RAW_SPACES_DATA=$(yabai -m query --spaces 2>/dev/null || echo "")
else
    log_debug "yabai not found for RAW_SPACES_DATA query."
fi

if [ -f "$CACHE_FILE" ]; then
  cached_state=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
  log_debug "Cached display state: $cached_state"
  if [ "$current_display_state" = "$cached_state" ] && [ -n "$current_display_state" ]; then
    # Display state unchanged, check if spaces actually changed
    if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
      current_spaces=$(echo "$RAW_SPACES_DATA" | jq -r '[.[] | "\(.display) \(.index)"] | sort | join(",")' 2>/dev/null || echo "")
      cached_spaces=$(cat "${CACHE_FILE}.spaces" 2>/dev/null || echo "")
      log_debug "Current spaces: $current_spaces, Cached spaces: $cached_spaces"
      if [ "$current_spaces" = "$cached_spaces" ] && [ -n "$current_spaces" ] && [ "$FORCE_REFRESH" != "1" ]; then
        log_debug "Spaces state unchanged. Exiting early."
        exit 0
      fi
      # Spaces changed, update cache
      log_debug "Updating ${CACHE_FILE}.spaces with: $current_spaces"
      echo "$current_spaces" > "${CACHE_FILE}.spaces" || true
    fi
  fi
fi

# Update display state cache
log_debug "Updating $CACHE_FILE with: $current_display_state"
echo "$current_display_state" > "$CACHE_FILE" || true

space_icons=("" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10")

# Fetch custom icons using high-performance C binary
if [ -x "$CONFIG_DIR/bin/state_manager" ]; then
    CUSTOM_ICON_DATA=$("$CONFIG_DIR/bin/state_manager" get-space-icons)
    log_debug "Custom icon data: $CUSTOM_ICON_DATA"
else
    # Fallback to empty if binary not found
    CUSTOM_ICON_DATA=""
    log_debug "state_manager binary not found."
fi

get_custom_icon() {
  local target="$1"
  # echo "DEBUG: Looking for custom icon for space $target in: $CUSTOM_ICON_DATA" >&2
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
    log_debug "Parsing RAW_SPACES_DATA into SPACE_LINES..."
    while IFS= read -r line; do
      SPACE_LINES+=("$line")
    done < <(printf '%s\n' "$RAW_SPACES_DATA" | jq -r '.[] | "\(.display) \(.index)"' | sort -k1,1n -k2,2n)
else
    log_debug "RAW_SPACES_DATA is empty or jq not found. Not parsing yabai spaces."
fi

log_debug "Detected ${#SPACE_LINES[@]} spaces from yabai or fallback processing."

if [ ${#SPACE_LINES[@]} -eq 0 ]; then
  FALLBACK_COUNT=${SKETCHYBAR_FALLBACK_SPACES:-10}
  log_debug "No yabai spaces found. Using fallback for ${FALLBACK_COUNT} spaces."
  for i in $(seq 1 "$FALLBACK_COUNT"); do
    SPACE_LINES+=("1 $i")
  done
fi

log_debug "Removing existing space items..."
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
  log_debug "Adding bracket for display $display with items: $*"
  sketchybar --add bracket "spaces.$display" "$@" \
             --set "spaces.$display" background.drawing=off \
                                      background.color="0x00000000" \
                                      background.corner_radius=0 \
                                      background.height=0 >&2
}

for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  space_index="${entry##* }"
  item="space.$space_index"

  log_debug "Processing space item: $item (Display: $display, Index: $space_index)"

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
  log_debug "Effective anchor for $item: $effective_anchor"

  # Check for custom icon from state.json first
  custom_icon=$(get_custom_icon "$space_index")
  if [ -n "$custom_icon" ]; then
    icon="$custom_icon"
    log_debug "Using custom icon for $item: $icon"
  else
    # Use default icon from array
    icon="${space_icons[icon_idx]}"
    log_debug "Using default icon for $item: $icon"
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
             --subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh >&2
  add_result=$?
  log_debug "sketchybar --add for $item exited with: $add_result"
  
  # Execute sketchybar --move command directly
  sketchybar --move "$item" after "$effective_anchor" >&2
  move_result=$?
  log_debug "sketchybar --move for $item exited with: $move_result"
  
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
  log_debug "Caching current spaces: $current_spaces"
  echo "$current_spaces" > "${CACHE_FILE}.spaces" || true
fi

# Add space creator button (+ icon)
PRIMARY_DISPLAY=1
if command -v yabai >/dev/null 2>&1; then
    PRIMARY_DISPLAY=$(yabai -m query --displays --display | jq .index 2>/dev/null || echo 1)
fi

log_debug "Adding space_creator button."
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
           --subscribe space_creator mouse.entered mouse.exited >&2

log_debug "Triggering space_mode_refresh."
sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true

if [ "$DEBUG_SPACES" != "0" ]; then
  elapsed=$((SECONDS - START_TIME))
  log_debug "spaces_setup.sh finished in ${elapsed}s."
fi
