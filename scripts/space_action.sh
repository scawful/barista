#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
SPACE_MANAGER_BIN="${SPACE_MANAGER_BIN:-$CONFIG_DIR/bin/space_manager}"
SPACE_CLOSE_CONFIRM_TTL_SEC="${SPACE_CLOSE_CONFIRM_TTL_SEC:-2}"
SPACE_SWAP_ARM_TTL_SEC="${SPACE_SWAP_ARM_TTL_SEC:-10}"
SPACE_SWAP_INDICATOR_ITEM="${SPACE_SWAP_INDICATOR_ITEM:-spaces.swap_indicator}"

run_with_timeout() {
  local timeout_s="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_s" "$@"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_s" "$@"
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$timeout_s" "$@"
    return $?
  fi
  "$@"
}

state_value() {
  local jq_query="$1"
  local fallback="$2"
  if [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
    local value
    value=$("$JQ_BIN" -r "$jq_query // empty" "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
      printf '%s' "$value"
      return 0
    fi
  fi
  printf '%s' "$fallback"
}

resolve_space_item_height() {
  local bar_height=""
  if command -v sketchybar >/dev/null 2>&1 && [ -n "$JQ_BIN" ]; then
    bar_height="$(sketchybar --query bar 2>/dev/null | "$JQ_BIN" -r '.height // empty' 2>/dev/null || true)"
  fi
  if [ -z "$bar_height" ] || [ "$bar_height" = "null" ]; then
    bar_height="$(state_value '.appearance.bar_height' '28')"
  fi
  if ! [ "$bar_height" -eq "$bar_height" ] 2>/dev/null; then
    bar_height=28
  fi

  local space_height=$((bar_height - 8))
  if [ "$space_height" -lt 20 ]; then
    space_height=20
  fi
  printf '%s' "$space_height"
}

normalize_close_mode() {
  case "$1" in
    off|confirm|direct)
      printf '%s' "$1"
      ;;
    *)
      printf '%s' "confirm"
      ;;
  esac
}

right_click_close_mode() {
  local mode
  mode=$(state_value '.spaces.right_click_close' 'confirm')
  normalize_close_mode "$mode"
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

normalize_reorder_mode() {
  local mode
  mode="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    off|modifiers|menu|swap_mode)
      printf '%s' "$mode"
      ;;
    *)
      printf '%s' "menu"
      ;;
  esac
}

reorder_mode() {
  local mode
  mode=$(state_value '.spaces.reorder_mode' 'menu')
  normalize_reorder_mode "$mode"
}

modifier_reorder_enabled() {
  local explicit
  explicit=$(state_value '.spaces.modifier_reorder_enabled' '')
  if [ -n "$explicit" ]; then
    [ "$(normalize_bool "$explicit")" = "true" ]
    return
  fi
  [ "$(reorder_mode)" = "modifiers" ]
}

context_menu_on_right_click() {
  local enabled
  enabled=$(state_value '.spaces.context_menu_on_right_click' 'true')
  [ "$(normalize_bool "$enabled")" = "true" ]
}

swap_indicator_enabled() {
  local enabled
  enabled=$(state_value '.spaces.swap_indicator' 'true')
  [ "$(normalize_bool "$enabled")" = "true" ]
}

modifier_has() {
  local needle="$1"
  local raw="${MODIFIER:-${modifiers:-}}"
  [ -n "$raw" ] || return 1
  case ",$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')," in
    *"$needle"*)
      return 0
      ;;
  esac
  return 1
}

confirm_file_for_space() {
  local space_idx="$1"
  printf '/tmp/barista_space_close_confirm_%s_%s' "$UID" "$space_idx"
}

confirm_recent() {
  local file="$1"
  [ -f "$file" ] || return 1
  local now mtime
  now=$(date +%s)
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  [ "$mtime" -gt 0 ] || return 1
  [ $(( now - mtime )) -le "$SPACE_CLOSE_CONFIRM_TTL_SEC" ]
}

mark_confirm() {
  local space_idx="$1"
  local file="$2"
  date +%s > "$file" 2>/dev/null || true
  sketchybar --set "space.$space_idx" \
    icon="󰅖" \
    icon.color=0xfff38ba8 \
    background.drawing=on \
    background.color=0x60f38ba8 >/dev/null 2>&1 || true
  nohup sh -c "
    sleep \"$SPACE_CLOSE_CONFIRM_TTL_SEC\"
    rm -f \"$file\" 2>/dev/null || true
    sketchybar --trigger space_change >/dev/null 2>&1 || true
  " >/dev/null 2>&1 &
}

swap_state_file() {
  printf '/tmp/barista_space_swap_state_%s' "$UID"
}

read_swap_source() {
  local file
  file=$(swap_state_file)
  [ -f "$file" ] || return 1

  local source_idx armed_at now
  source_idx=$(awk '{print $1}' "$file" 2>/dev/null || true)
  armed_at=$(awk '{print $2}' "$file" 2>/dev/null || true)
  case "$source_idx" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$armed_at" in
    ''|*[!0-9]*) return 1 ;;
  esac

  now=$(date +%s)
  if [ $(( now - armed_at )) -gt "$SPACE_SWAP_ARM_TTL_SEC" ]; then
    rm -f "$file" 2>/dev/null || true
    sketchybar --trigger space_change >/dev/null 2>&1 || true
    return 1
  fi

  printf '%s' "$source_idx"
}

clear_swap_state() {
  local file
  file=$(swap_state_file)
  rm -f "$file" 2>/dev/null || true
  sync_swap_indicator
  sketchybar --trigger space_change >/dev/null 2>&1 || true
}

arm_swap_state() {
  local space_idx="$1"
  local file
  file=$(swap_state_file)
  printf '%s %s\n' "$space_idx" "$(date +%s)" > "$file" 2>/dev/null || true
  sync_swap_indicator

  sketchybar --set "space.$space_idx" \
    icon="󰚗" \
    icon.color=0xfff9e2af \
    background.drawing=on \
    background.color=0x60f9e2af >/dev/null 2>&1 || true

  nohup sh -c "
    sleep \"$SPACE_SWAP_ARM_TTL_SEC\"
    if [ -f \"$file\" ]; then
      rm -f \"$file\" 2>/dev/null || true
      sketchybar --set \"$SPACE_SWAP_INDICATOR_ITEM\" drawing=off label='' background.drawing=off >/dev/null 2>&1 || true
      sketchybar --trigger space_change >/dev/null 2>&1 || true
    fi
  " >/dev/null 2>&1 &
}

ensure_swap_indicator_item() {
  local indicator_height
  indicator_height="$(resolve_space_item_height)"
  if ! swap_indicator_enabled; then
    return 0
  fi
  if sketchybar --query "$SPACE_SWAP_INDICATOR_ITEM" >/dev/null 2>&1; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" background.height="$indicator_height" >/dev/null 2>&1 || true
    return 0
  fi
  sketchybar --add item "$SPACE_SWAP_INDICATOR_ITEM" left >/dev/null 2>&1 || true
  sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
    icon="󰚗" \
    icon.color="0xfff9e2af" \
    label="" \
    label.color="0xfff9e2af" \
    label.padding_left=4 \
    label.padding_right=8 \
    background.drawing=off \
    background.color="0x00000000" \
    background.corner_radius=8 \
    background.height="$indicator_height" \
    drawing=off \
    click_script="$CONFIG_DIR/scripts/space_action.sh swap-cancel" >/dev/null 2>&1 || true
}

sync_swap_indicator() {
  local indicator_height
  indicator_height="$(resolve_space_item_height)"
  ensure_swap_indicator_item
  if ! swap_indicator_enabled; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" drawing=off >/dev/null 2>&1 || true
    return 0
  fi

  local source_idx
  source_idx=$(read_swap_source || true)
  if [ -n "$source_idx" ]; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
      drawing=on \
      icon="󰚗" \
      label="Swap $source_idx -> select target" \
      background.drawing=on \
      background.height="$indicator_height" \
      background.color="0x40f9e2af" >/dev/null 2>&1 || true
  else
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
      drawing=off \
      label="" \
      background.drawing=off >/dev/null 2>&1 || true
  fi
}

toggle_space_menu() {
  local space_idx="$1"
  sketchybar --set "space.$space_idx" popup.drawing=toggle >/dev/null 2>&1 || true
}

hide_space_menu() {
  local space_idx="$1"
  sketchybar --set "space.$space_idx" popup.drawing=off >/dev/null 2>&1 || true
}

refresh_space_items() {
  if [ -x "$CONFIG_DIR/plugins/refresh_spaces.sh" ]; then
    (CONFIG_DIR="$CONFIG_DIR" "$CONFIG_DIR/plugins/refresh_spaces.sh" >/dev/null 2>&1 || true) &
    return 0
  fi
  sketchybar --trigger space_change >/dev/null 2>&1 || true
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
}

focus_space() {
  local space_idx="$1"
  if [ -z "$YABAI_BIN" ]; then
    return 1
  fi
  run_with_timeout 1 "$YABAI_BIN" -m space --focus "$space_idx" >/dev/null 2>&1 || true
  sketchybar --trigger space_change >/dev/null 2>&1 || true
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
}

space_display() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --space "$space_idx" 2>/dev/null | "$JQ_BIN" -r '.display // empty'
}

space_has_focus() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --space "$space_idx" 2>/dev/null | "$JQ_BIN" -r '."has-focus" // false'
}

display_space_count() {
  local display_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null | "$JQ_BIN" -r 'length // 0'
}

alternate_space_on_display() {
  local display_idx="$1"
  local exclude_idx="$2"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null \
    | "$JQ_BIN" -r --argjson exclude "$exclude_idx" 'map(.index) | map(select(. != $exclude)) | .[0] // empty'
}

display_space_indices() {
  local display_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null \
    | "$JQ_BIN" -r 'map(.index) | sort | .[]'
}

display_indices() {
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --displays 2>/dev/null \
    | "$JQ_BIN" -r 'map(.index) | sort | .[]'
}

neighbor_display() {
  local display_idx="$1"
  local direction="$2"
  local displays=()
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    displays+=("$entry")
  done < <(display_indices)
  [ "${#displays[@]}" -gt 1 ] || return 1

  local pos=-1
  local i
  for i in "${!displays[@]}"; do
    if [ "${displays[$i]}" = "$display_idx" ]; then
      pos="$i"
      break
    fi
  done
  [ "$pos" -ge 0 ] || return 1

  if [ "$direction" = "prev" ]; then
    [ "$pos" -gt 0 ] || return 1
    printf '%s' "${displays[$((pos - 1))]}"
    return 0
  fi

  [ "$pos" -lt $(( ${#displays[@]} - 1 )) ] || return 1
  printf '%s' "${displays[$((pos + 1))]}"
}

neighbor_space_on_display() {
  local current_idx="$1"
  local direction="$2"
  local display_idx
  display_idx=$(space_display "$current_idx" || true)
  [ -n "$display_idx" ] || return 1

  local spaces=()
  local space_entry
  while IFS= read -r space_entry; do
    [ -n "$space_entry" ] || continue
    spaces+=("$space_entry")
  done < <(display_space_indices "$display_idx")
  [ "${#spaces[@]}" -gt 1 ] || return 1

  local pos=-1
  local i
  for i in "${!spaces[@]}"; do
    if [ "${spaces[$i]}" = "$current_idx" ]; then
      pos="$i"
      break
    fi
  done
  [ "$pos" -ge 0 ] || return 1

  if [ "$direction" = "left" ]; then
    [ "$pos" -gt 0 ] || return 1
    printf '%s' "${spaces[$((pos - 1))]}"
    return 0
  fi

  [ "$pos" -lt $(( ${#spaces[@]} - 1 )) ] || return 1
  printf '%s' "${spaces[$((pos + 1))]}"
}

move_space_to_display_neighbor() {
  local space_idx="$1"
  local direction="$2"
  [ -n "$YABAI_BIN" ] || return 1

  local current_display target_display
  current_display=$(space_display "$space_idx" || true)
  [ -n "$current_display" ] || return 1

  case "$direction" in
    prev)
      target_display=$(neighbor_display "$current_display" "prev" || true)
      ;;
    next)
      target_display=$(neighbor_display "$current_display" "next" || true)
      ;;
    *)
      return 1
      ;;
  esac
  [ -n "$target_display" ] || return 0

  run_with_timeout 1 "$YABAI_BIN" -m space "$space_idx" --display "$target_display" >/dev/null 2>&1 || true
  refresh_space_items
}

move_space() {
  local from_idx="$1"
  local to_idx="$2"
  [ -n "$YABAI_BIN" ] || return 1
  if [ "$from_idx" = "$to_idx" ]; then
    return 0
  fi
  if [ -x "$SPACE_MANAGER_BIN" ]; then
    "$SPACE_MANAGER_BIN" move "$from_idx" "$to_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$from_idx" --move "$to_idx" >/dev/null 2>&1 || true
  fi
  refresh_space_items
}

swap_spaces() {
  local from_idx="$1"
  local to_idx="$2"
  [ -n "$YABAI_BIN" ] || return 1
  if [ "$from_idx" = "$to_idx" ]; then
    return 0
  fi
  if [ -x "$SPACE_MANAGER_BIN" ]; then
    "$SPACE_MANAGER_BIN" swap "$from_idx" "$to_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$from_idx" --swap "$to_idx" >/dev/null 2>&1 || true
  fi
  refresh_space_items
}

reorder_space_relative() {
  local space_idx="$1"
  local direction="$2"
  local neighbor
  neighbor=$(neighbor_space_on_display "$space_idx" "$direction" || true)
  [ -n "$neighbor" ] || return 0
  move_space "$space_idx" "$neighbor"
}

destroy_space() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] || return 1

  local display_idx
  display_idx=$(space_display "$space_idx" || true)
  if [ -z "$display_idx" ]; then
    return 1
  fi

  local count
  count=$(display_space_count "$display_idx" || echo 0)
  if [ "${count:-0}" -le 1 ]; then
    echo "Refusing to destroy last space on display $display_idx" >&2
    return 1
  fi

  local focused
  focused=$(space_has_focus "$space_idx" || echo false)
  if [ "$focused" = "true" ]; then
    local alt
    alt=$(alternate_space_on_display "$display_idx" "$space_idx" || true)
    if [ -n "$alt" ]; then
      run_with_timeout 1 "$YABAI_BIN" -m space --focus "$alt" >/dev/null 2>&1 || true
    fi
  fi

  if [ -x "$SPACE_MANAGER_BIN" ]; then
    "$SPACE_MANAGER_BIN" destroy "$space_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$space_idx" --destroy >/dev/null 2>&1 || true
  fi

  refresh_space_items
}

create_space() {
  local target_display="${1:-active}"
  [ -n "$YABAI_BIN" ] || return 1

  case "$target_display" in
    ""|active)
      run_with_timeout 1 "$YABAI_BIN" -m display --focus mouse >/dev/null 2>&1 || true
      ;;
    *)
      run_with_timeout 1 "$YABAI_BIN" -m display --focus "$target_display" >/dev/null 2>&1 || true
      ;;
  esac

  if [ -x "$SPACE_MANAGER_BIN" ]; then
    "$SPACE_MANAGER_BIN" create >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space --create >/dev/null 2>&1 || true
  fi

  refresh_space_items
}

is_right_click() {
  local raw_button="${BUTTON:-${MOUSE_BUTTON:-${CLICK_BUTTON:-}}}"
  local button
  button=$(printf '%s' "$raw_button" | tr '[:upper:]' '[:lower:]')
  case "$button" in
    right|2|secondary)
      return 0
      ;;
  esac
  return 1
}

handle_close_request() {
  local space_idx="$1"
  local source="${2:-right_click}"
  local mode
  mode=$(right_click_close_mode)
  case "$mode" in
    off)
      if [ "$source" = "menu" ]; then
        destroy_space "$space_idx"
      else
        focus_space "$space_idx"
      fi
      ;;
    direct)
      destroy_space "$space_idx"
      ;;
    confirm)
      local confirm_file
      confirm_file=$(confirm_file_for_space "$space_idx")
      if confirm_recent "$confirm_file"; then
        rm -f "$confirm_file" 2>/dev/null || true
        destroy_space "$space_idx"
      else
        mark_confirm "$space_idx" "$confirm_file"
      fi
      ;;
  esac
}

handle_space_click() {
  local space_idx="$1"

  if is_right_click; then
    if context_menu_on_right_click; then
      toggle_space_menu "$space_idx"
    else
      handle_close_request "$space_idx" "right_click"
    fi
    return 0
  fi

  if modifier_reorder_enabled && modifier_has "shift"; then
    if modifier_has "cmd" || modifier_has "command"; then
      reorder_space_relative "$space_idx" "right"
    else
      reorder_space_relative "$space_idx" "left"
    fi
    hide_space_menu "$space_idx"
    return 0
  fi

  local armed_space
  armed_space=$(read_swap_source || true)
  if [ -n "$armed_space" ]; then
    if [ "$armed_space" = "$space_idx" ]; then
      clear_swap_state
      hide_space_menu "$space_idx"
      return 0
    fi
    swap_spaces "$armed_space" "$space_idx"
    clear_swap_state
    hide_space_menu "$space_idx"
    return 0
  fi

  focus_space "$space_idx"
}

usage() {
  cat <<'USAGE'
Usage: space_action.sh <command> [args]

Commands:
  create [--display <index|active>]
  click --space <index>
  focus --space <index>
  destroy --space <index>
  menu --space <index>
  menu-close --space <index>
  move-left --space <index>
  move-right --space <index>
  move-display-prev --space <index>
  move-display-next --space <index>
  swap-arm --space <index>
  swap-cancel
USAGE
}

parse_space_arg() {
  local space_idx=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --space)
        shift
        space_idx="${1:-}"
        ;;
    esac
    shift || true
  done
  printf '%s' "$space_idx"
}

command="${1:-}"
shift || true

sync_swap_indicator >/dev/null 2>&1 || true

case "$command" in
  create)
    target_display="active"
    while [ $# -gt 0 ]; do
      case "$1" in
        --display)
          shift
          target_display="${1:-active}"
          ;;
      esac
      shift || true
    done
    create_space "$target_display"
    ;;
  click)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    handle_space_click "$space_idx"
    ;;
  focus)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    focus_space "$space_idx"
    ;;
  destroy)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    destroy_space "$space_idx"
    ;;
  menu)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    toggle_space_menu "$space_idx"
    ;;
  menu-close)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    handle_close_request "$space_idx" "menu"
    hide_space_menu "$space_idx"
    ;;
  move-left)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    reorder_space_relative "$space_idx" "left"
    hide_space_menu "$space_idx"
    ;;
  move-right)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    reorder_space_relative "$space_idx" "right"
    hide_space_menu "$space_idx"
    ;;
  move-display-prev)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    move_space_to_display_neighbor "$space_idx" "prev"
    hide_space_menu "$space_idx"
    ;;
  move-display-next)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    move_space_to_display_neighbor "$space_idx" "next"
    hide_space_menu "$space_idx"
    ;;
  swap-arm)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    arm_swap_state "$space_idx"
    hide_space_menu "$space_idx"
    ;;
  swap-cancel)
    space_idx=$(parse_space_arg "$@")
    clear_swap_state
    if [ -n "$space_idx" ]; then
      hide_space_menu "$space_idx"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
