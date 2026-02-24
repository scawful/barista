#!/bin/bash

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
RETRY_FILE="$CONFIG_DIR/.spaces_retry"
SIG_CACHE_FILE="$CONFIG_DIR/.spaces_signatures"
STATE_FILE="$CONFIG_DIR/state.json"
SPACE_ACTION_SCRIPT="$CONFIG_DIR/scripts/space_action.sh"
SPACE_MANAGER_BIN="$CONFIG_DIR/bin/space_manager"
# OPTIMIZED: Reduced retry attempts and delays for faster startup
MAX_SPACE_QUERY_ATTEMPTS=3
SPACE_QUERY_DELAY=0.05

normalize_creator_mode() {
  case "$1" in
    primary|active|per_display)
      printf '%s' "$1"
      ;;
    *)
      printf '%s' "per_display"
      ;;
  esac
}

resolve_creator_mode() {
  local mode=""
  if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
    mode=$(jq -r '.spaces.creator_mode // empty' "$STATE_FILE" 2>/dev/null || true)
  fi
  normalize_creator_mode "${mode:-per_display}"
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      printf '%s' "true"
      ;;
    *)
      printf '%s' "false"
      ;;
  esac
}

resolve_diff_updates_enabled() {
  local enabled="true"
  if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
    enabled=$(jq -r '.spaces.experimental_diff_updates // empty' "$STATE_FILE" 2>/dev/null || true)
  fi
  [ "$(normalize_bool "${enabled:-true}")" = "true" ]
}

space_click_action() {
  local space_index="${1:-}"
  if [ -x "$SPACE_ACTION_SCRIPT" ]; then
    printf '%s click --space %s' "$SPACE_ACTION_SCRIPT" "$space_index"
    return 0
  fi
  printf '%s %s' "$FOCUS_SCRIPT" "$space_index"
}

creator_click_action() {
  local target_display="${1:-active}"
  if [ -x "$SPACE_ACTION_SCRIPT" ]; then
    printf '%s create --display %s' "$SPACE_ACTION_SCRIPT" "$target_display"
    return 0
  fi
  if [ -x "$SPACE_MANAGER_BIN" ]; then
    printf '%s create' "$SPACE_MANAGER_BIN"
    return 0
  fi
  printf '%s' 'yabai -m space --create'
}

space_menu_action() {
  local action="${1:-}"
  local space_index="${2:-}"
  if [ -x "$SPACE_ACTION_SCRIPT" ]; then
    printf '%s %s --space %s' "$SPACE_ACTION_SCRIPT" "$action" "$space_index"
    return 0
  fi
  case "$action" in
    menu-close)
      printf '%s %s' "$FOCUS_SCRIPT" "$space_index"
      ;;
    move-left|move-right|swap-arm|swap-cancel)
      printf '%s' ''
      ;;
  esac
}

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

# OPTIMIZED: Reduced retry delay from 400ms to 150ms
schedule_spaces_retry() {
  local now last
  now=$(date +%s)
  last=$(cat "$RETRY_FILE" 2>/dev/null || echo 0)
  if [ $((now - last)) -lt 1 ]; then
    return 0
  fi
  printf '%s' "$now" > "$RETRY_FILE" 2>/dev/null || true
  (
    sleep 0.15
    CONFIG_DIR="$CONFIG_DIR" "$CONFIG_DIR/plugins/refresh_spaces.sh" >/dev/null 2>&1 || true
  ) &
}

CREATOR_MODE="$(resolve_creator_mode)"

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

# OPTIMIZED: Reduced polling iterations for faster startup
for i in {1..10}; do
  if sketchybar --query front_app >/dev/null 2>&1; then
    break
  fi
  sleep 0.02
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

declare -a DISPLAY_IDS=()
for entry in "${SPACE_LINES[@]}"; do
  display="${entry%% *}"
  [ -n "$display" ] || continue
  seen=0
  for existing_display in "${DISPLAY_IDS[@]-}"; do
    if [ "$existing_display" = "$display" ]; then
      seen=1
      break
    fi
  done
  if [ "$seen" -eq 0 ]; then
    DISPLAY_IDS+=("$display")
  fi
done

declare -a VISIBLE_SPACE_LINES=()
if [ -n "$RAW_SPACES_DATA" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    VISIBLE_SPACE_LINES+=("$line")
  done < <(printf '%s\n' "$RAW_SPACES_DATA" | jq -r '.[] | select(."is-visible" == true) | "\(.display) \(.index)"')
fi

visible_space_for_display() {
  local target_display="${1:-}"
  local pair pair_display pair_space
  for pair in "${VISIBLE_SPACE_LINES[@]-}"; do
    pair_display="${pair%% *}"
    pair_space="${pair##* }"
    if [ "$pair_display" = "$target_display" ] && [ -n "$pair_space" ]; then
      printf '%s' "$pair_space"
      return 0
    fi
  done
  return 1
}

join_lines_with_comma() {
  local line
  local out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -n "$out" ]; then
      out="$out,$line"
    else
      out="$line"
    fi
  done
  printf '%s' "$out"
}

topology_signature() {
  printf '%s\n' "${SPACE_LINES[@]-}" | join_lines_with_comma
}

visible_signature() {
  printf '%s\n' "${VISIBLE_SPACE_LINES[@]-}" | join_lines_with_comma
}

creator_targets_signature() {
  printf '%s\n' "${CREATOR_TARGETS[@]-}" | join_lines_with_comma
}

load_signature() {
  local key="$1"
  [ -f "$SIG_CACHE_FILE" ] || return 1
  awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=")+1)}' "$SIG_CACHE_FILE" 2>/dev/null | tail -n 1
}

write_signatures() {
  local topology="$1"
  local visible="$2"
  {
    printf 'topology=%s\n' "$topology"
    printf 'visible=%s\n' "$visible"
  } > "$SIG_CACHE_FILE" 2>/dev/null || true
}

if [ -d "$ICON_CACHE_DIR" ]; then
  ACTIVE_SPACES=" "
  for entry in "${SPACE_LINES[@]}"; do
    space_index="${entry##* }"
    ACTIVE_SPACES="${ACTIVE_SPACES}${space_index} "
  done
  shopt -s nullglob
  for cache_file in "$ICON_CACHE_DIR"/*; do
    [ -f "$cache_file" ] || continue
    cache_name="${cache_file##*/}"
    case " $ACTIVE_SPACES " in
      *" $cache_name "*) ;;
      *) rm -f "$cache_file" 2>/dev/null || true ;;
    esac
  done
  shopt -u nullglob
fi

# Prepare batch command
declare -a SB_ARGS=()

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
  click_action="$(space_click_action "$space_index")"

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
                          click_script="$click_action")
  SB_ARGS+=(--subscribe "$item" mouse.entered mouse.exited space_change space_mode_refresh)

  if [ -x "$SPACE_ACTION_SCRIPT" ]; then
    menu_prefix="$item.menu"
    menu_close_action="$(space_menu_action "menu-close" "$space_index")"
    menu_move_left_action="$(space_menu_action "move-left" "$space_index")"
    menu_move_right_action="$(space_menu_action "move-right" "$space_index")"
    menu_swap_action="$(space_menu_action "swap-arm" "$space_index")"
    menu_swap_cancel_action="$(space_menu_action "swap-cancel" "$space_index")"

    SB_ARGS+=(--add item "$menu_prefix.close" "popup.$item")
    SB_ARGS+=(--set "$menu_prefix.close" \
                    icon="󰅖" \
                    icon.color="0xfff38ba8" \
                    label="Close Space" \
                    label.color="0xfff2cdcd" \
                    script="$CONFIG_DIR/plugins/popup_hover.sh" \
                    click_script="$menu_close_action")

    SB_ARGS+=(--add item "$menu_prefix.left" "popup.$item")
    SB_ARGS+=(--set "$menu_prefix.left" \
                    icon="󰁍" \
                    icon.color="0xffa6e3a1" \
                    label="Move Left" \
                    script="$CONFIG_DIR/plugins/popup_hover.sh" \
                    click_script="$menu_move_left_action")

    SB_ARGS+=(--add item "$menu_prefix.right" "popup.$item")
    SB_ARGS+=(--set "$menu_prefix.right" \
                    icon="󰁔" \
                    icon.color="0xffa6e3a1" \
                    label="Move Right" \
                    script="$CONFIG_DIR/plugins/popup_hover.sh" \
                    click_script="$menu_move_right_action")

    SB_ARGS+=(--add item "$menu_prefix.swap" "popup.$item")
    SB_ARGS+=(--set "$menu_prefix.swap" \
                    icon="󰚗" \
                    icon.color="0xfff9e2af" \
                    label="Swap: Select Target" \
                    script="$CONFIG_DIR/plugins/popup_hover.sh" \
                    click_script="$menu_swap_action")

    SB_ARGS+=(--add item "$menu_prefix.swap_cancel" "popup.$item")
    SB_ARGS+=(--set "$menu_prefix.swap_cancel" \
                    icon="󰜺" \
                    icon.color="0xffa6adc8" \
                    label="Cancel Swap" \
                    script="$CONFIG_DIR/plugins/popup_hover.sh" \
                    click_script="$menu_swap_cancel_action")
  fi

  if [ -n "$last_item" ]; then
    SB_ARGS+=(--move "$item" after "$last_item")
  fi
  
  last_item="$item"
  SPACE_ITEMS+=("$item")
done

# Add space creator button(s)
PRIMARY_DISPLAY=1
if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  PRIMARY_DISPLAY=$(yabai -m query --displays --display 2>/dev/null | jq -r '.index // 1' 2>/dev/null || echo 1)
fi

declare -a CREATOR_TARGETS=()
case "$CREATOR_MODE" in
  per_display)
    if [ "$fallback_active" -eq 1 ]; then
      CREATOR_TARGETS=("active")
    else
      CREATOR_TARGETS=("${DISPLAY_IDS[@]-}")
    fi
    ;;
  active)
    CREATOR_TARGETS=("active")
    ;;
  primary|*)
    if [ "$fallback_active" -eq 1 ]; then
      CREATOR_TARGETS=("active")
    else
      CREATOR_TARGETS=("$PRIMARY_DISPLAY")
    fi
    ;;
esac

if [ ${#CREATOR_TARGETS[@]} -eq 0 ]; then
  CREATOR_TARGETS=("active")
fi

DIFF_UPDATES_ENABLED=0
if resolve_diff_updates_enabled; then
  DIFF_UPDATES_ENABLED=1
fi

TOPOLOGY_SIG="$(topology_signature)|creator_mode=$CREATOR_MODE|creator_targets=$(creator_targets_signature)"
VISIBLE_SIG="$(visible_signature)"

if [ "$DIFF_UPDATES_ENABLED" -eq 1 ]; then
  cached_topology="$(load_signature topology || true)"
  if [ -n "$cached_topology" ] && [ "$cached_topology" = "$TOPOLOGY_SIG" ]; then
    fast_path_ok=1
    for entry in "${SPACE_LINES[@]-}"; do
      space_index="${entry##* }"
      if ! item_exists "space.$space_index"; then
        fast_path_ok=0
        break
      fi
      if [ -x "$SPACE_ACTION_SCRIPT" ]; then
        for menu_item in \
          "space.$space_index.menu.close" \
          "space.$space_index.menu.left" \
          "space.$space_index.menu.right" \
          "space.$space_index.menu.swap" \
          "space.$space_index.menu.swap_cancel"; do
          if ! item_exists "$menu_item"; then
            fast_path_ok=0
            break
          fi
        done
      fi
      if [ "$fast_path_ok" -eq 0 ]; then
        break
      fi
    done
    if [ "$fast_path_ok" -eq 1 ]; then
      for creator_target in "${CREATOR_TARGETS[@]-}"; do
        creator_item="space_creator"
        if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
          creator_item="space_creator.$creator_target"
        fi
        if ! item_exists "$creator_item"; then
          fast_path_ok=0
          break
        fi
      done
    fi

    if [ "$fast_path_ok" -eq 1 ]; then
      for entry in "${SPACE_LINES[@]-}"; do
        space_index="${entry##* }"
        click_action="$(space_click_action "$space_index")"
        sketchybar --set "space.$space_index" click_script="$click_action" >/dev/null 2>&1 || true
      done

      for creator_target in "${CREATOR_TARGETS[@]-}"; do
        creator_item="space_creator"
        if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
          creator_item="space_creator.$creator_target"
        fi
        creator_cmd="$(creator_click_action "$creator_target")"
        creator_space=""
        creator_ignore_association="on"
        if [ "$creator_target" != "active" ]; then
          creator_space="$(visible_space_for_display "$creator_target" || true)"
          if [ -n "$creator_space" ]; then
            creator_ignore_association="off"
          fi
        fi
        if [ -n "$creator_space" ]; then
          sketchybar --set "$creator_item" \
            display="$creator_target" \
            ignore_association="$creator_ignore_association" \
            space="$creator_space" \
            click_script="$creator_cmd" >/dev/null 2>&1 || true
        else
          sketchybar --set "$creator_item" \
            display="$creator_target" \
            ignore_association="$creator_ignore_association" \
            click_script="$creator_cmd" >/dev/null 2>&1 || true
        fi
      done

      write_signatures "$TOPOLOGY_SIG" "$VISIBLE_SIG"
      sketchybar --trigger space_change >/dev/null 2>&1 || true
      sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
      exit 0
    fi
  fi
fi

declare -a CREATOR_ITEMS=()
for creator_target in "${CREATOR_TARGETS[@]-}"; do
  creator_item="space_creator"
  if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
    creator_item="space_creator.$creator_target"
  fi
  creator_cmd="$(creator_click_action "$creator_target")"
  creator_space=""
  creator_ignore_association="on"
  if [ "$creator_target" != "active" ]; then
    creator_space="$(visible_space_for_display "$creator_target" || true)"
    if [ -n "$creator_space" ]; then
      creator_ignore_association="off"
    fi
  fi

  SB_ARGS+=(--add item "$creator_item" left)
  SB_ARGS+=(--set "$creator_item" \
                  display="$creator_target" \
                  ignore_association="$creator_ignore_association" \
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
                  click_script="$creator_cmd")
  if [ -n "$creator_space" ]; then
    SB_ARGS+=(--set "$creator_item" space="$creator_space")
  fi
  SB_ARGS+=(--subscribe "$creator_item" mouse.entered mouse.exited)
  if [ -n "$last_item" ]; then
    SB_ARGS+=(--move "$creator_item" after "$last_item")
  fi
  last_item="$creator_item"
  CREATOR_ITEMS+=("$creator_item")
done

# Remove existing spaces only for full rebuild path
sketchybar --remove '/space\..*/' >/dev/null 2>&1 || true
sketchybar --remove '/spaces\..*/' >/dev/null 2>&1 || true
sketchybar --remove '/space_creator\..*/' >/dev/null 2>&1 || true
sketchybar --remove space_creator >/dev/null 2>&1 || true

# Execute all commands in one single call
sketchybar "${SB_ARGS[@]}"
write_signatures "$TOPOLOGY_SIG" "$VISIBLE_SIG"


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
        for creator_item in "${CREATOR_ITEMS[@]-}"; do
          sketchybar --move "$creator_item" after "$last" >/dev/null 2>&1 || true
          last="$creator_item"
        done
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
