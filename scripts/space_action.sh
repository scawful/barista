#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
SPACE_MANAGER_BIN="${SPACE_MANAGER_BIN:-$CONFIG_DIR/bin/space_manager}"
SPACE_CLOSE_CONFIRM_TTL_SEC="${SPACE_CLOSE_CONFIRM_TTL_SEC:-2}"

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
  sketchybar --set "space.$space_idx" icon.color=0xfff38ba8 >/dev/null 2>&1 || true
  (
    sleep "$SPACE_CLOSE_CONFIRM_TTL_SEC"
    rm -f "$file" 2>/dev/null || true
    sketchybar --trigger space_change >/dev/null 2>&1 || true
  ) &
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

handle_space_click() {
  local space_idx="$1"

  if is_right_click; then
    local mode
    mode=$(right_click_close_mode)
    case "$mode" in
      off)
        focus_space "$space_idx"
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
  *)
    usage
    exit 1
    ;;
esac
