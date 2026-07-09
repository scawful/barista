#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
SKHD_BIN="${SKHD_BIN:-$(command -v skhd || true)}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
FRONT_APP_SCRIPT="${BARISTA_FRONT_APP_SCRIPT:-$CONFIG_DIR/plugins/front_app.sh}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$CONFIG_DIR/scripts/front_app_context.sh}"
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-$CONFIG_DIR/scripts/runtime_context.sh}"
YABAI_LABEL="${BARISTA_YABAI_LABEL:-}"
YABAI_LABEL_NEW="com.asmvik.yabai"
YABAI_LABEL_OLD="com.koekeishiya.yabai"
SPACE_FOCUS_TIMEOUT_SEC="${SPACE_FOCUS_TIMEOUT_SEC:-1}"
SPACE_QUERY_TIMEOUT_SEC="${SPACE_QUERY_TIMEOUT_SEC:-1}"
SPACE_FOCUS_LOCK_STALE_SEC="${SPACE_FOCUS_LOCK_STALE_SEC:-2}"
SPACE_FOCUS_LOCK_DIR="/tmp/yabai_control_space_focus_${UID}.lock"
SPACE_FOCUS_OSASCRIPT_FALLBACK="${SPACE_FOCUS_OSASCRIPT_FALLBACK:-0}"
REQUESTED_COMMAND="${1:-}"

if [[ -z "$YABAI_BIN" ]]; then
  case "$REQUESTED_COMMAND" in
    shortcuts|wm-mode|mode|set-mode|app-default)
      ;;
    *)
      echo "yabai not found in PATH." >&2
      exit 1
      ;;
  esac
fi

python3_bin() {
  command -v python3 2>/dev/null || command -v /usr/bin/python3 2>/dev/null || true
}

yabai_service_labels() {
  local labels=()
  if [[ -n "$YABAI_LABEL" ]]; then
    labels+=("$YABAI_LABEL")
  fi
  labels+=("$YABAI_LABEL_NEW" "$YABAI_LABEL_OLD")

  local seen=""
  local label
  for label in "${labels[@]}"; do
    [[ -z "$label" ]] && continue
    case " $seen " in
      *" $label "*) ;;
      *)
        seen="${seen:+$seen }$label"
        printf '%s\n' "$label"
        ;;
    esac
  done
}

yabai_has_service_file() {
  local label="$1"
  [[ -f "$HOME/Library/LaunchAgents/${label}.plist" ]]
}

yabai_launchctl_kickstart() {
  local label
  for label in $(yabai_service_labels); do
    if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1 || yabai_has_service_file "$label"; then
      if launchctl kickstart -kp "gui/${UID}/${label}" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done
  return 1
}

require_jq() {
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is required for this command." >&2
    exit 1
  fi
}

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

acquire_space_focus_lock() {
  if mkdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null; then
    return 0
  fi

  local now mtime age
  now=$(date +%s)
  mtime=$(stat -f %m "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || echo 0)
  age=$(( now - mtime ))
  if (( age > SPACE_FOCUS_LOCK_STALE_SEC )); then
    rmdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || true
    mkdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null
    return $?
  fi
  return 1
}

release_space_focus_lock() {
  rmdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || true
}

current_space_index() {
  require_jq
  local current

  current=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window 2>/dev/null \
      | "$JQ_BIN" -r '.space // empty' \
      | head -n 1
  )
  if [[ -n "$current" && "$current" != "null" ]]; then
    echo "$current"
    return 0
  fi

  current=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display 2>/dev/null \
      | "$JQ_BIN" -r '.[] | select(.["has-focus"] == true or .["is-visible"] == true) | .index' \
      | head -n 1
  )
  if [[ -n "$current" && "$current" != "null" ]]; then
    echo "$current"
    return 0
  fi

  return 1
}

current_space_layout() {
  require_jq
  local layout

  layout=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display 2>/dev/null \
      | "$JQ_BIN" -r '.[] | select(.["has-focus"] == true or .["is-visible"] == true) | .type' \
      | head -n 1
  )
  if [[ -n "$layout" && "$layout" != "null" ]]; then
    echo "$layout"
    return 0
  fi

  return 1
}

display_space_indices() {
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display | "$JQ_BIN" -r '.[].index'
}

all_spaces_json() {
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces 2>/dev/null || true
}

neighbor_space_index() {
  local direction="$1"
  mapfile -t spaces < <(display_space_indices)
  local count=${#spaces[@]}
  if (( count == 0 )); then
    return 1
  fi

  local current
  current=$(current_space_index)
  local pos=-1
  for i in "${!spaces[@]}"; do
    if [[ "${spaces[$i]}" == "$current" ]]; then
      pos=$i
      break
    fi
  done

  if (( pos < 0 )); then
    return 1
  fi

  if [[ "$direction" == "next" ]]; then
    echo "${spaces[$(( (pos + 1) % count ))]}"
  else
    echo "${spaces[$(( (pos - 1 + count) % count ))]}"
  fi
}

focused_window_json() {
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window 2>/dev/null || true
}

window_id_from_json() {
  local window_json="${1:-}"
  [ -n "$window_json" ] || return 0
  printf '%s\n' "$window_json" | "$JQ_BIN" -r '.id // empty' 2>/dev/null | head -n 1
}

window_space_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '.space // empty' 2>/dev/null \
    | head -n 1
}

window_is_floating_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '."is-floating" // false' 2>/dev/null \
    | head -n 1
}

window_is_fullscreen_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '."has-fullscreen-zoom" // ."is-native-fullscreen" // false' 2>/dev/null \
    | head -n 1
}

window_display_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '.display // empty' 2>/dev/null \
    | head -n 1
}

window_layer_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '.layer // empty' 2>/dev/null \
    | head -n 1
}

window_sub_layer_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -r '."sub-layer" // empty' 2>/dev/null \
    | head -n 1
}

window_is_topmost_for_id() {
  local window_id="${1:-}"
  local current_sub_layer current_layer

  [ -n "$window_id" ] || return 1
  current_sub_layer="$(window_sub_layer_for_id "$window_id")"
  if [[ "$current_sub_layer" == "above" ]]; then
    return 0
  fi

  current_layer="$(window_layer_for_id "$window_id")"
  [[ "$current_layer" == "above" ]]
}

clear_window_topmost_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0

  if window_is_topmost_for_id "$window_id"; then
    "$YABAI_BIN" -m window "$window_id" --sub-layer auto >/dev/null 2>&1 || true
  fi
}

set_window_floating_for_id() {
  local window_id="${1:-}"
  local desired="${2:-}"
  local current

  [ -n "$window_id" ] || return 0
  [ -n "$desired" ] || return 0

  current="$(window_is_floating_for_id "$window_id")"
  if [[ "$desired" == "true" && "$current" != "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle float >/dev/null 2>&1 || true
  elif [[ "$desired" == "false" && "$current" == "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle float >/dev/null 2>&1 || true
  fi
}

set_window_fullscreen_for_id() {
  local window_id="${1:-}"
  local desired="${2:-}"
  local current

  [ -n "$window_id" ] || return 0
  [ -n "$desired" ] || return 0

  current="$(window_is_fullscreen_for_id "$window_id")"
  if [[ "$desired" == "true" && "$current" != "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle zoom-fullscreen >/dev/null 2>&1 || true
  elif [[ "$desired" == "false" && "$current" == "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle zoom-fullscreen >/dev/null 2>&1 || true
  fi
}

refresh_space_state() {
  if [[ -n "${SKETCHYBAR_BIN:-}" ]]; then
    "$SKETCHYBAR_BIN" --trigger space_mode_refresh >/dev/null 2>&1 || true
  fi
}

refresh_front_app_state() {
  if [[ -z "${SKETCHYBAR_BIN:-}" ]]; then
    return 0
  fi

  if [[ -x "$RUNTIME_CONTEXT_SCRIPT" ]]; then
    BARISTA_CONFIG_DIR="$CONFIG_DIR" \
      BARISTA_YABAI_BIN="$YABAI_BIN" \
      BARISTA_JQ_BIN="$JQ_BIN" \
      "$RUNTIME_CONTEXT_SCRIPT" refresh front-app >/dev/null 2>&1 || true
  fi

  if [[ -x "$FRONT_APP_SCRIPT" ]]; then
    BARISTA_CONFIG_DIR="$CONFIG_DIR" \
      BARISTA_YABAI_BIN="$YABAI_BIN" \
      BARISTA_JQ_BIN="$JQ_BIN" \
      NAME=front_app \
      SENDER=routine \
      "$FRONT_APP_SCRIPT" >/dev/null 2>&1 || true
  fi
}

run_space_command() {
  "$YABAI_BIN" -m space "$@"
  refresh_space_state
  refresh_front_app_state
}

space_toggle_padding_gap() {
  "$YABAI_BIN" -m space --toggle padding
  "$YABAI_BIN" -m space --toggle gap
  refresh_space_state
  refresh_front_app_state
}

space_layout_for_index() {
  local target_space="${1:-}"
  [ -n "$target_space" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --space "$target_space" 2>/dev/null \
    | "$JQ_BIN" -r '.type // empty' 2>/dev/null \
    | head -n 1
}

normalize_window_for_space_layout() {
  local window_id="${1:-}"
  local target_space="${2:-}"
  local target_layout floating_state

  [ -n "$window_id" ] || return 0
  [ -n "$target_space" ] || return 0

  target_layout="$(space_layout_for_index "$target_space")"
  case "$target_layout" in
    float)
      floating_state="$(window_is_floating_for_id "$window_id")"
      if [[ "$floating_state" != "true" ]]; then
        "$YABAI_BIN" -m window "$window_id" --toggle float >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

apply_window_move_policy() {
  local policy="${1:-preserve}"
  local window_id="${2:-}"
  local target_space="${3:-}"

  [ -n "$window_id" ] || return 0
  [ -n "$target_space" ] || return 0

  case "$policy" in
    adopt_destination)
      adopt_window_to_space_layout "$window_id" "$target_space"
      ;;
    preserve|*)
      normalize_window_for_space_layout "$window_id" "$target_space"
      ;;
  esac
}

adopt_window_to_space_layout() {
  local window_id="${1:-}"
  local target_space="${2:-}"
  local target_layout floating_state

  [ -n "$window_id" ] || return 0
  [ -n "$target_space" ] || return 0

  target_layout="$(space_layout_for_index "$target_space")"
  floating_state="$(window_is_floating_for_id "$window_id")"
  case "$target_layout" in
    float)
      if [[ "$floating_state" != "true" ]]; then
        "$YABAI_BIN" -m window "$window_id" --toggle float >/dev/null 2>&1 || true
      fi
      ;;
    bsp|stack)
      if [[ "$floating_state" = "true" ]]; then
        "$YABAI_BIN" -m window "$window_id" --toggle float >/dev/null 2>&1 || true
      fi
      ;;
  esac

  clear_window_topmost_for_id "$window_id"
}

preferred_space_for_layout() {
  local target_layout="${1:-}"
  local current_space="${2:-0}"
  local current_display="${3:-0}"
  local spaces_json

  [ -n "$target_layout" ] || return 1
  spaces_json="$(all_spaces_json)"
  [ -n "$spaces_json" ] || return 1

  printf '%s\n' "$spaces_json" | "$JQ_BIN" -r \
    --arg layout "$target_layout" \
    --argjson current_space "$current_space" \
    --argjson current_display "$current_display" '
      map(select((.type // "") == $layout))
      | sort_by(
          (if (.display // 0) == $current_display then 0 else 1 end),
          (if (.index // 0) == $current_space then 1 else 0 end),
          (.display // 0),
          (.index // 0)
        )
      | map(select((.index // 0) != $current_space))
      | .[0].index // empty
    ' 2>/dev/null | head -n 1
}

focused_window_id() {
  local focused_json
  focused_json="$(focused_window_json)"
  window_id_from_json "$focused_json"
}

move_window_with_rules() {
  local policy="${BARISTA_WINDOW_MOVE_POLICY:-preserve}"

  if [[ "${1:-}" == "--policy" ]]; then
    policy="${2:-preserve}"
    shift 2
  fi

  if [[ -z "$JQ_BIN" ]]; then
    "$YABAI_BIN" -m window "$@"
    return
  fi

  local focused_json window_id target_space
  focused_json="$(focused_window_json)"
  window_id="$(window_id_from_json "$focused_json")"

  if [[ -z "$window_id" ]]; then
    "$YABAI_BIN" -m window "$@"
    return
  fi

  "$YABAI_BIN" -m window "$window_id" "$@"

  target_space="$(window_space_for_id "$window_id")"
  if [[ -n "$target_space" && "$target_space" != "null" ]]; then
    apply_window_move_policy "$policy" "$window_id" "$target_space"
  fi

  refresh_front_app_state
}

window_adopt_space_mode() {
  local window_id target_space

  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  target_space="${1:-}"
  if [[ -z "$target_space" ]]; then
    target_space="$(window_space_for_id "$window_id")"
  fi
  [[ -n "$target_space" ]] || return 1

  adopt_window_to_space_layout "$window_id" "$target_space"
  refresh_front_app_state
}

window_move_to_layout_space() {
  local target_layout="${1:-}"
  local window_id current_space current_display target_space

  [[ -n "$target_layout" ]] || return 1
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  current_space="$(window_space_for_id "$window_id")"
  current_display="$(window_display_for_id "$window_id")"
  target_space="$(preferred_space_for_layout "$target_layout" "${current_space:-0}" "${current_display:-0}")"
  [[ -n "$target_space" ]] || return 1

  move_window_with_rules --space "$target_space"
}

space_focus_safe() {
  local target="$1"
  local direction="${2:-$target}"
  if run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" "$YABAI_BIN" -m space --focus "$target" >/dev/null 2>&1; then
    return 0
  fi

  if space_focus_events_fallback "$direction"; then
    return 0
  fi

  echo "space focus failed (scripting addition likely missing)" >&2
  return 1
}

space_focus_events_fallback() {
  local direction="$1"
  if [[ "$SPACE_FOCUS_OSASCRIPT_FALLBACK" != "1" ]]; then
    return 1
  fi
  case "$direction" in
    next)
      run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" osascript -e 'tell application "System Events" to key code 124 using control down' >/dev/null 2>&1 || true
      return 0
      ;;
    prev)
      run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" osascript -e 'tell application "System Events" to key code 123 using control down' >/dev/null 2>&1 || true
      return 0
      ;;
  esac

  return 1
}

space_focus_wrap() {
  local direction="$1"
  if ! acquire_space_focus_lock; then
    # Drop repeated keypresses while a focus command is already in-flight.
    return 0
  fi

  local rc=0
  run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" "$YABAI_BIN" -m space --focus "$direction" >/dev/null 2>&1 || rc=$?
  release_space_focus_lock

  if (( rc == 0 )); then
    return 0
  fi
  if (( rc == 124 )); then
    # Yabai focus command timed out; skip additional focus attempts for this press.
    return 0
  fi

  if space_focus_events_fallback "$direction"; then
    return 0
  fi

  echo "space focus failed (scripting addition likely missing)" >&2
  return 1
}

display_focus_wrap() {
  local direction="$1"
  local fallback

  case "$direction" in
    prev) fallback="last" ;;
    next) fallback="first" ;;
    *) echo "Usage: $0 display-focus-prev-wrap|display-focus-next-wrap" >&2; return 1 ;;
  esac

  if "$YABAI_BIN" -m display --focus "$direction" >/dev/null 2>&1 \
    || "$YABAI_BIN" -m display --focus "$fallback" >/dev/null 2>&1; then
    refresh_space_state
    refresh_front_app_state
    return 0
  fi

  echo "display focus failed: $direction" >&2
  return 1
}

window_focus_direction() {
  local direction="$1"
  [ -n "$direction" ] || return 1

  if "$YABAI_BIN" -m window --focus "$direction" >/dev/null 2>&1 \
    || "$YABAI_BIN" -m display --focus "$direction" >/dev/null 2>&1; then
    refresh_space_state
    refresh_front_app_state
    return 0
  fi

  echo "window focus failed: $direction" >&2
  return 1
}

window_swap_direction() {
  local direction="$1"
  local rc=0
  [ -n "$direction" ] || return 1

  "$YABAI_BIN" -m window --swap "$direction" || rc=$?
  refresh_front_app_state
  return "$rc"
}

window_space_wrap() {
  local direction="$1"
  local target
  target=$(neighbor_space_index "$direction") || return 1
  move_window_with_rules --space "$target"
}

space_focus_app() {
  local app="$1"
  if [[ -z "$app" ]]; then
    echo "Usage: $0 space-focus-app <AppName>" >&2
    exit 1
  fi
  require_jq
  local space
  space=$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows | "$JQ_BIN" -r --arg app "$app" '.[] | select(.app == $app) | .space' | head -n 1)
  if [[ -z "$space" ]]; then
    echo "No window found for app: $app" >&2
    exit 1
  fi
  space_focus_safe "$space"
}

window_center() {
  "$YABAI_BIN" -m window --grid 4:4:1:1:2:2
  refresh_front_app_state
}

window_toggle_property() {
  local property="${1:-}"
  [ -n "$property" ] || return 1
  "$YABAI_BIN" -m window --toggle "$property"
  refresh_front_app_state
}

window_toggle_topmost() {
  local window_id target_sub_layer

  if [[ -z "$JQ_BIN" ]]; then
    "$YABAI_BIN" -m window --raise >/dev/null 2>&1 || true
    return 0
  fi

  window_id="$(focused_window_id)"
  if [[ -z "$window_id" ]]; then
    "$YABAI_BIN" -m window --raise >/dev/null 2>&1 || true
    return 0
  fi

  if window_is_topmost_for_id "$window_id"; then
    target_sub_layer="auto"
  else
    target_sub_layer="above"
  fi

  "$YABAI_BIN" -m window "$window_id" --sub-layer "$target_sub_layer" >/dev/null 2>&1 \
    || "$YABAI_BIN" -m window --raise >/dev/null 2>&1 \
    || true
  refresh_front_app_state
}

window_preset_utility() {
  local window_id
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  set_window_fullscreen_for_id "$window_id" false
  set_window_floating_for_id "$window_id" true
  clear_window_topmost_for_id "$window_id"
  "$YABAI_BIN" -m window "$window_id" --grid 4:4:1:1:2:2 >/dev/null 2>&1 || true
  refresh_front_app_state
}

window_preset_focus() {
  local window_id target_space
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  set_window_fullscreen_for_id "$window_id" false
  target_space="$(window_space_for_id "$window_id")"
  if [[ -n "$target_space" ]]; then
    adopt_window_to_space_layout "$window_id" "$target_space"
  fi
  "$YABAI_BIN" -m space --balance >/dev/null 2>&1 || true
  refresh_space_state
  refresh_front_app_state
}

window_preset_presentation() {
  local window_id
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  set_window_fullscreen_for_id "$window_id" true
  refresh_front_app_state
}

window_preset_tile_here() {
  local window_id
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  set_window_fullscreen_for_id "$window_id" false
  window_adopt_space_mode
}


normalize_wm_mode_arg() {
  local mode="${1:-}"
  mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    off|false|none|disable|disabled|manual|bar)
      echo "disabled"
      ;;
    optional|opt|auto-if-running|auto_if_running)
      echo "optional"
      ;;
    required|require|enabled|enable|on|yabai)
      echo "required"
      ;;
    auto|"")
      echo "auto"
      ;;
    *)
      echo "$mode"
      ;;
  esac
}

read_state_wm_mode() {
  local py
  py="$(python3_bin)"
  if [[ -n "$py" && -f "$STATE_FILE" ]]; then
    "$py" - "$STATE_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    print(((data.get('modes') or {}).get('window_manager')) or 'auto')
except Exception:
    print('auto')
PY
    return 0
  fi
  echo "auto"
}

write_state_wm_mode() {
  local mode="$1" py
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 required to update state" >&2; return 1; }
  mkdir -p "$(dirname "$STATE_FILE")"
  "$py" - "$STATE_FILE" "$mode" <<'PY'
import json, os, sys
path, mode = sys.argv[1:3]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
modes = data.get('modes')
if not isinstance(modes, dict):
    modes = {}
data['modes'] = modes
modes['window_manager'] = mode
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, ensure_ascii=False)
os.replace(tmp, path)
PY
}

reload_barista_after_config_change() {
  local reload_script="$CONFIG_DIR/plugins/reload_sketchybar.sh"
  if [[ -x "$reload_script" ]]; then
    "$reload_script" >/dev/null 2>&1 || true
  elif [[ -n "${SKETCHYBAR_BIN:-}" ]]; then
    "$SKETCHYBAR_BIN" --reload >/dev/null 2>&1 || true
  fi
}

wm_mode_command() {
  local target="${1:-}"
  if [[ -z "$target" || "$target" == "current" || "$target" == "show" ]]; then
    read_state_wm_mode
    return 0
  fi

  target="$(normalize_wm_mode_arg "$target")"
  case "$target" in
    disabled|optional|required|auto) ;;
    *) echo "Usage: $0 wm-mode <required|optional|disabled|auto>" >&2; return 1 ;;
  esac

  write_state_wm_mode "$target"
  # Do not auto-start yabai/skhd from a popup mode switch. Starting yabai can
  # trigger macOS Developer Tools Access prompts if the scripting addition or
  # service authorization is stale. Keep mode changes cheap/reversible; use
  # `yabai_control.sh start` or `doctor --fix` explicitly when service repair is desired.
  reload_barista_after_config_change
  echo "window_manager: $target"
}

slugify_app_name() {
  local py app="$1"
  py="$(python3_bin)"
  if [[ -n "$py" ]]; then
    "$py" - "$app" <<'PY'
import re, sys
slug = re.sub(r'[^a-z0-9]+', '-', sys.argv[1].lower()).strip('-')
print(slug or 'app')
PY
  else
    printf '%s' "$app" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
  fi
}

regex_escape_app_name() {
  local py app="$1"
  py="$(python3_bin)"
  if [[ -n "$py" ]]; then
    "$py" - "$app" <<'PY'
import re, sys
print('^' + re.escape(sys.argv[1]) + '$')
PY
  else
    printf '^%s$' "$app"
  fi
}

current_app_name() {
  require_jq
  local focused_json app
  focused_json="$(focused_window_json)"
  app="$(printf '%s\n' "$focused_json" | "$JQ_BIN" -r '.app // empty' 2>/dev/null | head -n 1)"
  if [[ -n "$app" && "$app" != "null" ]]; then
    echo "$app"
    return 0
  fi
  if [[ -x "$FRONT_APP_CONTEXT_SCRIPT" ]]; then
    app="$("$FRONT_APP_CONTEXT_SCRIPT" --mode focused-space 2>/dev/null \
      | awk -F'\t' '$1 == "app_name" { print $2; exit }' || true)"
    if [[ -n "$app" && "$app" != "null" ]]; then
      echo "$app"
      return 0
    fi
  fi
  echo "No focused yabai window/app." >&2
  return 1
}

rule_label_for_app() {
  echo "barista-default-$(slugify_app_name "$1")"
}

normalize_app_default_mode() {
  local mode="${1:-}"
  mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    float|floating|utility|manual)
      echo "float"
      ;;
    tile|tiled|bsp|stack|focus|managed)
      echo "tile"
      ;;
    unset|remove|clear|off|none)
      echo "unset"
      ;;
    *)
      echo "$mode"
      ;;
  esac
}

state_write_app_default() {
  local app="$1" mode="$2" app_regex="$3" label="$4" py
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 required to update app defaults" >&2; return 1; }
  mkdir -p "$(dirname "$STATE_FILE")"
  "$py" - "$STATE_FILE" "$app" "$mode" "$app_regex" "$label" <<'PY'
import json, os, sys
path, app, mode, app_regex, label = sys.argv[1:6]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
wd = data.get('window_defaults')
if not isinstance(wd, dict):
    wd = {}
apps = wd.get('apps')
if not isinstance(apps, dict):
    apps = {}
wd['apps'] = apps
data['window_defaults'] = wd
apps[app] = {
    'mode': mode,
    'app_regex': app_regex,
    'rule_label': label,
    'manage': 'off' if mode == 'float' else 'on',
    'sub_layer': 'normal',
}
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, ensure_ascii=False)
os.replace(tmp, path)
PY
}

state_unset_app_default() {
  local app="$1" py
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 required to update app defaults" >&2; return 1; }
  [[ -f "$STATE_FILE" ]] || return 0
  "$py" - "$STATE_FILE" "$app" <<'PY'
import json, os, sys
path, app = sys.argv[1:3]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {}
apps = (((data if isinstance(data, dict) else {}).get('window_defaults') or {}).get('apps') or {})
if isinstance(apps, dict):
    apps.pop(app, None)
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as fh:
    json.dump(data if isinstance(data, dict) else {}, fh, ensure_ascii=False)
os.replace(tmp, path)
PY
}

remove_yabai_rule_label() {
  local label="$1" idx
  [[ -n "${YABAI_BIN:-}" && -n "$label" ]] || return 0
  "$YABAI_BIN" -m rule --remove "$label" >/dev/null 2>&1 || true
  if [[ -n "${JQ_BIN:-}" ]]; then
    "$YABAI_BIN" -m rule --list 2>/dev/null \
      | "$JQ_BIN" -r --arg label "$label" '.[] | select((.label // "") == $label) | .index // empty' 2>/dev/null \
      | sort -rn \
      | while IFS= read -r idx; do
          [[ -n "$idx" ]] && "$YABAI_BIN" -m rule --remove "$idx" >/dev/null 2>&1 || true
        done
  fi
}

install_yabai_app_rule() {
  local app="$1" mode="$2" app_regex label
  app_regex="$(regex_escape_app_name "$app")"
  label="$(rule_label_for_app "$app")"
  remove_yabai_rule_label "$label"
  if [[ -n "${YABAI_BIN:-}" ]]; then
    case "$mode" in
      float)
        "$YABAI_BIN" -m rule --add label="$label" app="$app_regex" manage=off sub-layer=normal >/dev/null 2>&1 || true
        ;;
      tile)
        "$YABAI_BIN" -m rule --add label="$label" app="$app_regex" manage=on sub-layer=normal >/dev/null 2>&1 || true
        ;;
    esac
  fi
  state_write_app_default "$app" "$mode" "$app_regex" "$label"
}

apply_current_window_default() {
  local mode="$1"
  case "$mode" in
    float)
      window_preset_utility >/dev/null 2>&1 || true
      ;;
    tile)
      window_preset_tile_here >/dev/null 2>&1 || true
      ;;
  esac
}

app_default_set() {
  local app="$1" mode="$2"
  [[ -n "$app" && -n "$mode" ]] || { echo "Usage: $0 app-default set <App Name> <float|tile>" >&2; return 1; }
  mode="$(normalize_app_default_mode "$mode")"
  case "$mode" in
    float|tile) ;;
    *) echo "Usage: $0 app-default set <App Name> <float|tile>" >&2; return 1 ;;
  esac
  install_yabai_app_rule "$app" "$mode"
  echo "app default: $app -> $mode"
}

app_default_unset() {
  local app="$1" label
  [[ -n "$app" ]] || { echo "Usage: $0 app-default unset <App Name>" >&2; return 1; }
  label="$(rule_label_for_app "$app")"
  remove_yabai_rule_label "$label"
  state_unset_app_default "$app"
  echo "app default removed: $app"
}

app_default_current() {
  local mode="$(normalize_app_default_mode "${1:-}")" app
  case "$mode" in
    float|tile|unset) ;;
    *) echo "Usage: $0 app-default-current <float|tile|unset>" >&2; return 1 ;;
  esac
  app="$(current_app_name)"
  if [[ "$mode" == "unset" ]]; then
    app_default_unset "$app"
  else
    app_default_set "$app" "$mode"
    apply_current_window_default "$mode"
  fi
  refresh_front_app_state
}

app_default_list() {
  local py
  py="$(python3_bin)"
  if [[ -z "$py" || ! -f "$STATE_FILE" ]]; then
    echo "no app defaults"
    return 0
  fi
  "$py" - "$STATE_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {}
apps = (((data if isinstance(data, dict) else {}).get('window_defaults') or {}).get('apps') or {})
if not apps:
    print('no app defaults')
else:
    for app in sorted(apps):
        rec = apps[app] if isinstance(apps[app], dict) else {}
        print(f"{app}: {rec.get('mode', 'unknown')}")
PY
}

app_default_command() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    set)
      if (( $# < 2 )); then
        echo "Usage: $0 app-default set <App Name> <float|tile>" >&2
        return 1
      fi
      local mode="${!#}"
      local app="${*:1:$#-1}"
      app_default_set "$app" "$mode"
      ;;
    unset|remove|clear)
      app_default_unset "$*"
      ;;
    list|ls|"")
      app_default_list
      ;;
    *)
      echo "Usage: $0 app-default <list|set <App Name> <float|tile>|unset <App Name>>" >&2
      return 1
      ;;
  esac
}

restart_yabai() {
  if "$YABAI_BIN" --restart-service >/dev/null 2>&1; then
    echo "yabai restarted"
    return 0
  fi
  if yabai_launchctl_kickstart; then
    echo "yabai restarted via launchctl"
    return 0
  fi
  if "$YABAI_BIN" --install-service >/dev/null 2>&1; then
    if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
      echo "yabai restarted via installed service"
      return 0
    fi
  fi
  if command -v brew >/dev/null 2>&1; then
    if brew services restart yabai >/dev/null 2>&1; then
      echo "yabai restarted via brew"
      return 0
    fi
  fi
  start_yabai
}

start_yabai() {
  if pgrep -x yabai >/dev/null 2>&1; then
    echo "yabai already running"
    return 0
  fi
  if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
    echo "yabai started"
    return 0
  fi
  if "$YABAI_BIN" --install-service >/dev/null 2>&1; then
    if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
      echo "yabai started via installed service"
      return 0
    fi
  fi
  if yabai_launchctl_kickstart; then
    echo "yabai started via launchctl"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    if brew services start yabai >/dev/null 2>&1; then
      echo "yabai started via brew"
      return 0
    fi
  fi
  echo "Unable to start yabai." >&2
  return 1
}

skhd_config_path() {
  if [[ -n "${SKHD_CONFIG:-}" ]]; then
    echo "$SKHD_CONFIG"
    return 0
  fi
  if [[ -f "$HOME/.config/skhd/skhdrc" ]]; then
    echo "$HOME/.config/skhd/skhdrc"
    return 0
  fi
  if [[ -f "$HOME/.skhdrc" ]]; then
    echo "$HOME/.skhdrc"
    return 0
  fi
  echo "$HOME/.config/skhd/skhdrc"
}

skhd_shortcuts_path() {
  echo "$HOME/.config/skhd/barista_shortcuts.conf"
}

skhd_expected_load_line() {
  printf '.load "%s"' "$(skhd_shortcuts_path)"
}

skhd_error_log() {
  local user
  user=$(id -un 2>/dev/null || echo "user")
  echo "/tmp/skhd_${user}.err.log"
}

skhd_error_recent() {
  local log="$1"
  local now
  local mtime
  now=$(date +%s)
  mtime=$(stat -f %m "$log" 2>/dev/null || echo 0)
  (( now - mtime < 3600 ))
}

skhd_running() {
  pgrep -x skhd >/dev/null 2>&1
}

skhd_pid_count() {
  local count
  count=$( (pgrep -x skhd 2>/dev/null || true) | wc -l | tr -d ' ' )
  echo "${count:-0}"
}

skhd_kill_all() {
  pkill -x skhd >/dev/null 2>&1 || true
}

skhd_start() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  if "$SKHD_BIN" --start-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services start skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

skhd_restart() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  if "$SKHD_BIN" --restart-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services restart skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

skhd_reload() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  "$SKHD_BIN" --reload >/dev/null 2>&1
}

skhd_check_load_line() {
  local config="$1"
  if [[ ! -f "$config" ]]; then
    echo "skhd config not found: $config"
    return 1
  fi
  if grep -q "barista_shortcuts.conf" "$config"; then
    if grep -Eq '^[[:space:]]*\.load[[:space:]]+"[^"]*barista_shortcuts\.conf"' "$config"; then
      return 0
    fi
    echo "skhd config loads barista_shortcuts.conf without double quotes"
    return 2
  fi
  echo "skhd config missing .load for barista shortcuts"
  return 3
}

expand_user_path() {
  local value="${1:-}"
  case "$value" in
    "~/"*) printf '%s\n' "$HOME/${value#\~/}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

skhd_loaded_files() {
  local config="$1"
  [[ -f "$config" ]] || return 0
  printf '%s\n' "$config"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\.load[[:space:]]+\"([^\"]+)\" ]]; then
      expand_user_path "${BASH_REMATCH[1]}"
    fi
  done < "$config"
}

skhd_shortcut_inventory_tsv() {
  local config="$1"
  local files=()
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(skhd_loaded_files "$config")
  ((${#files[@]} > 0)) || return 0

  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function strip_inline_comment(value) {
      sub(/[[:space:]]+#.*/, "", value)
      return trim(value)
    }
    function classify(file, command) {
      if (file ~ /keychron/) return "keychron"
      if (command ~ /yabai_control_wrapper\.sh/) return "barista-wrapper"
      if (command ~ /\/yabai_control\.sh/) return "barista-yabai"
      if (command ~ /reload_sketchybar\.sh/) return "reload"
      if (command ~ /(^|[[:space:]])yabai[[:space:]]+-m/) return "raw-yabai"
      if (command ~ /(^|[[:space:]])open[[:space:]]+/) return "app-launch"
      if (command ~ /(^|[[:space:]])sketchybar([[:space:]]|$)/) return "sketchybar"
      return "command"
    }
    function combo_looks_like_binding(combo) {
      combo = trim(combo)
      return combo ~ /(^|[[:space:]])(-|\+|<)[[:space:]]/ \
        || combo ~ /^(f[0-9]+|leader|hyper|ctrl|alt|cmd|shift)([[:space:]]|$)/
    }
    function emit(status, line_no, file, combo, command, desc) {
      command = strip_inline_comment(command)
      desc = trim(desc)
      if (desc == "") desc = "-"
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", status, file, line_no, trim(combo), desc, command, classify(file, command)
    }
    function parse_binding(raw, status, line_no, file, desc, line, combo, command) {
      line = raw
      if (line ~ /^[[:space:]]*::/) return 0
      if (line !~ /[;:]/) return 0
      combo = line
      sub(/[;:].*$/, "", combo)
      command = line
      sub(/^[^;:]+[;:][[:space:]]*/, "", command)
      combo = trim(combo)
      command = strip_inline_comment(command)
      if (combo == "" || command == "" || combo ~ /^\.load/) return 0
      if (status == "disabled" && !combo_looks_like_binding(combo)) return 0
      emit(status, line_no, file, combo, command, desc)
      return 1
    }
    {
      if (FNR == 1) pending_desc = ""
      original = $0
      if (original ~ /^[[:space:]]*#/) {
        commented = original
        sub(/^[[:space:]]*#[[:space:]]?/, "", commented)
        if (parse_binding(commented, "disabled", FNR, FILENAME, "commented binding") == 0) {
          pending_desc = commented
        }
        next
      }
      if (original ~ /^[[:space:]]*($|\.load|::)/) next
      if (parse_binding(original, "active", FNR, FILENAME, pending_desc) == 1) {
        pending_desc = ""
      }
    }
  ' "${files[@]}" 2>/dev/null
}

shortcut_command_missing_target() {
  local command="${1:-}"
  local token=""

  case "$command" in
    \"*\")
      token="${command#\"}"
      token="${token%%\"*}"
      ;;
    \'*\')
      token="${command#\'}"
      token="${token%%\'*}"
      ;;
    *)
      token="${command%%[[:space:];]*}"
      ;;
  esac

  [[ -n "$token" ]] || return 1
  token="$(expand_user_path "$token")"
  case "$token" in
    /*)
      [[ -e "$token" ]] || {
        printf '%s\n' "$token"
        return 0
      }
      ;;
  esac
  return 1
}

skhd_shortcut_inventory_enriched_tsv() {
  local config="$1"
  local status file line combo desc command kind missing
  while IFS=$'\t' read -r status file line combo desc command kind; do
    [[ -n "${status:-}" ]] || continue
    missing="$(shortcut_command_missing_target "$command" || true)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$file" "$line" "$combo" "$desc" "$command" "$kind" "$missing"
  done < <(skhd_shortcut_inventory_tsv "$config")
}

skhd_shortcut_inventory_summary() {
  local config="$1"
  local duplicate_count
  duplicate_count="$(skhd_duplicate_bindings "$config" | awk 'END { print NR + 0 }')"
  skhd_shortcut_inventory_enriched_tsv "$config" | awk -F'\t' -v duplicates="$duplicate_count" '
    $1 == "active" { active++ }
    $1 == "disabled" { disabled++ }
    $6 ~ /(^|[[:space:]])yabai[[:space:]]+-m/ && $1 == "active" { raw++ }
    $8 != "" && $1 == "active" { missing++ }
    END {
      printf "active=%d disabled=%d duplicates=%d raw_yabai=%d missing_targets=%d\n", active + 0, disabled + 0, duplicates + 0, raw + 0, missing + 0
    }
  '
}

summary_value() {
  local summary="${1:-}"
  local key="${2:-}"
  printf '%s\n' "$summary" | tr ' ' '\n' | awk -F= -v key="$key" '$1 == key { print $2; exit }'
}

run_shortcuts_inventory() {
  local format="text"
  case "${1:-}" in
    --json) format="json" ;;
    ""|"--text") ;;
    *) echo "Usage: $0 shortcuts [--json]" >&2; return 1 ;;
  esac

  local skhd_config
  skhd_config="$(skhd_config_path)"

  if [[ "$format" == "json" ]]; then
    local py
    py="$(python3_bin)"
    [[ -n "$py" ]] || { echo "python3 not found; cannot render JSON" >&2; return 1; }
    skhd_shortcut_inventory_enriched_tsv "$skhd_config" | "$py" -c '
import csv, json, sys
rows = []
for row in csv.reader(sys.stdin, delimiter="\t"):
    if len(row) < 8:
        continue
    rows.append({
        "status": row[0],
        "source": row[1],
        "line": int(row[2]) if row[2].isdigit() else row[2],
        "combo": row[3],
        "description": row[4],
        "command": row[5],
        "kind": row[6],
        "missing_target": row[7] or None,
    })
print(json.dumps({"shortcuts": rows}, indent=2, sort_keys=True))
'
    return 0
  fi

  echo "skhd shortcuts inventory"
  echo "config: $skhd_config"
  skhd_print_loaded_files "$skhd_config"
  echo "summary: $(skhd_shortcut_inventory_summary "$skhd_config")"
  echo
  skhd_shortcut_inventory_enriched_tsv "$skhd_config" | awk -F'\t' '
    current != $2 {
      current = $2
      printf "\n[%s]\n", current
    }
    {
      missing = ($8 == "") ? "" : sprintf(" missing=%s", $8)
      printf "  %-8s %-18s %-15s %s%s\n", $1, $4, $7, $5, missing
      printf "           %s\n", $6
    }
  '
}

rules_expected_json() {
  cat <<'JSON'
[
  {"label":"System utilities","app":"^(System Settings|System Information|Activity Monitor|Calculator|Dictionary|Software Update|Archive Utility)$","sub_layer":"normal"},
  {"label":"Media utilities","app":"^(Photo Booth|QuickTime Player|VLC)$","sub_layer":"normal"},
  {"label":"Finder","app":"^Finder$","sub_layer":"normal"},
  {"label":"About This Mac","app":"System Information","title":"About This Mac","sub_layer":"normal"},
  {"label":"Emacs","app":"^Emacs$","sub_layer":"normal"},
  {"label":"Mesen","app":"^(Mesen|Mesen2.*)$","sub_layer":"normal"},
  {"label":"Yaze","app":"^Yaze$","sub_layer":"normal"},
  {"label":"Oracle manager","app":"^oracle_manager_gui$","sub_layer":"normal"},
  {"label":"Alfred","app":"^Alfred$","sub_layer":"normal"},
  {"label":"Raycast","app":"^Raycast$","sub_layer":"normal"},
  {"label":"Taskwarrior","app":"^Taskwarrior$","sub_layer":"normal"},
  {"label":"Lazygit","app":"^Lazygit$","title":"lazygit","sub_layer":"normal"},
  {"label":"Barista binary","app":"^barista_config$","sub_layer":"normal"},
  {"label":"Barista Config","app":"^Barista Config$","sub_layer":"normal"},
  {"label":"Barista app","app":"^Barista$","sub_layer":"normal"},
  {"label":"Barista Control Panel","app":"^Barista Control Panel$","sub_layer":"normal"},
  {"label":"BaristaControlPanel","app":"^BaristaControlPanel$","sub_layer":"normal"},
  {"label":"AFS Studio binary","app":"^afs_studio$","sub_layer":"normal"},
  {"label":"AFS Studio","app":"^AFS Studio$","sub_layer":"normal"},
  {"label":"AFS Browser binary","app":"^afs-browser$","sub_layer":"normal"},
  {"label":"AFS Browser","app":"^AFS Browser$","sub_layer":"normal"},
  {"label":"Cortex binary","app":"^cortex$","sub_layer":"normal"},
  {"label":"Cortex","app":"^Cortex$","sub_layer":"normal"},
  {"label":"System Manual binary","app":"^sys_manual$","sub_layer":"normal"},
  {"label":"System Manual","app":"^System Manual$","sub_layer":"normal"},
  {"label":"Picture View","app":"^(Picture View|PictureView)$","sub_layer":"normal"}
]
JSON
}

run_rules_audit() {
  local format="text"
  case "${1:-}" in
    --json) format="json" ;;
    ""|"--text") ;;
    *) echo "Usage: $0 rules-audit [--json]" >&2; return 1 ;;
  esac

  local py rules_json windows_json expected_json
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 not found; cannot audit rules" >&2; return 1; }

  rules_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m rule --list 2>/dev/null || true)"
  windows_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows 2>/dev/null || true)"
  expected_json="${BARISTA_RULES_AUDIT_EXPECTED_JSON:-$(rules_expected_json)}"
  [[ -n "$rules_json" ]] || rules_json="[]"
  [[ -n "$windows_json" ]] || windows_json="[]"

  RULES_JSON="$rules_json" WINDOWS_JSON="$windows_json" EXPECTED_RULES_JSON="$expected_json" AUDIT_FORMAT="$format" "$py" - <<'PY'
import json
import os
import re
import sys

def load_json(name, fallback):
    raw = os.environ.get(name, "")
    try:
        return json.loads(raw) if raw else fallback
    except json.JSONDecodeError:
        return fallback

rules = load_json("RULES_JSON", [])
windows = load_json("WINDOWS_JSON", [])
expected = load_json("EXPECTED_RULES_JSON", [])
output_format = os.environ.get("AUDIT_FORMAT", "text")
findings = []

def rule_matches_expected(rule, item):
    if rule.get("app", "") != item.get("app", ""):
        return False
    if item.get("title") and rule.get("title", "") != item.get("title", ""):
        return False
    return True

def is_unmanaged_normal(rule):
    return rule.get("manage") is False and rule.get("sub-layer") == "normal"

def window_matches_rule(window, rule):
    app_pattern = rule.get("app") or ""
    title_pattern = rule.get("title") or ""
    app = window.get("app") or ""
    title = window.get("title") or ""
    try:
        if app_pattern and not re.search(app_pattern, app):
            return False
        if title_pattern and not re.search(title_pattern, title):
            return False
        return bool(app_pattern)
    except re.error:
        return False

for item in expected:
    matching = [rule for rule in rules if rule_matches_expected(rule, item)]
    if not matching:
        findings.append({
            "severity": "error",
            "type": "missing-rule",
            "label": item.get("label"),
            "app": item.get("app"),
            "title": item.get("title", ""),
            "message": f"missing expected unmanaged-normal rule: {item.get('label')}",
        })
        continue
    if not any(is_unmanaged_normal(rule) for rule in matching):
        findings.append({
            "severity": "error",
            "type": "rule-without-normal",
            "label": item.get("label"),
            "app": item.get("app"),
            "message": f"expected rule is not manage=off sub-layer=normal: {item.get('label')}",
        })

unmanaged_normal_rules = [rule for rule in rules if is_unmanaged_normal(rule)]
for window in windows:
    if window.get("is-minimized") is True:
        continue
    sub_layer = window.get("sub-layer") or ""
    layer = window.get("layer") or ""
    if sub_layer == "above" or layer == "above":
        findings.append({
            "severity": "info",
            "type": "manual-topmost",
            "id": window.get("id"),
            "app": window.get("app", ""),
            "title": window.get("title", ""),
            "message": "window is manually topmost/above",
        })
    if any(window_matches_rule(window, rule) for rule in unmanaged_normal_rules):
        if sub_layer not in ("normal", "auto", "above"):
            findings.append({
                "severity": "warn",
                "type": "live-policy-mismatch",
                "id": window.get("id"),
                "app": window.get("app", ""),
                "title": window.get("title", ""),
                "sub_layer": sub_layer,
                "message": "live unmanaged utility window is not normal",
            })

family_hints = [
    ("Barista", re.compile(r"barista", re.I)),
    ("Cortex", re.compile(r"cortex", re.I)),
    ("Oracle", re.compile(r"oracle", re.I)),
    ("AFS", re.compile(r"\bafs\b|afs[_ -]", re.I)),
]
seen_variant = set()
for window in windows:
    if window.get("is-minimized") is True:
        continue
    app = window.get("app") or ""
    if not app or any(window_matches_rule(window, rule) for rule in unmanaged_normal_rules):
        continue
    for family, pattern in family_hints:
        if pattern.search(app):
            key = (family, app)
            if key in seen_variant:
                continue
            seen_variant.add(key)
            findings.append({
                "severity": "warn",
                "type": "app-variant-review",
                "family": family,
                "app": app,
                "message": f"review app-name variant for {family}: {app}",
            })

summary = {
    "expected_rules": len(expected),
    "present_expected_rules": sum(1 for item in expected if any(rule_matches_expected(rule, item) for rule in rules)),
    "rules": len(rules),
    "windows": len(windows),
    "findings": len(findings),
    "errors": sum(1 for item in findings if item["severity"] == "error"),
    "warnings": sum(1 for item in findings if item["severity"] == "warn"),
    "info": sum(1 for item in findings if item["severity"] == "info"),
}

if output_format == "json":
    print(json.dumps({"summary": summary, "findings": findings}, indent=2, sort_keys=True))
else:
    print("yabai rules audit")
    print(f"expected unmanaged rules: {summary['present_expected_rules']}/{summary['expected_rules']} present")
    print(f"rules: {summary['rules']} windows: {summary['windows']}")
    print(f"findings: {summary['errors']} errors, {summary['warnings']} warnings, {summary['info']} info")
    for finding in findings:
        parts = [finding["severity"], finding["type"]]
        if finding.get("id") is not None:
            parts.append(f"id={finding['id']}")
        if finding.get("app"):
            parts.append(f"app={finding['app']}")
        if finding.get("title"):
            parts.append(f"title={finding['title']}")
        print("  " + " ".join(parts) + " - " + finding["message"])
    if not findings:
        print("rules audit: ok")

sys.exit(1 if summary["errors"] else 0)
PY
}

skhd_print_loaded_files() {
  local config="$1"
  local file
  echo "skhd loaded files:"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ -f "$file" ]]; then
      echo "  ok  $file"
    else
      echo "  miss $file" >&2
    fi
  done < <(skhd_loaded_files "$config")
}

skhd_duplicate_bindings() {
  local config="$1"
  local files=()
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(skhd_loaded_files "$config")
  ((${#files[@]} > 0)) || return 0
  awk '
    /^[[:space:]]*($|#)/ { next }
    /^[[:space:]]*::/ { next }
    /^[[:space:]]*[^:]+[;:]/ {
      combo = $0
      sub(/[;:].*$/, "", combo)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", combo)
      if (combo == "" || combo ~ /^\\.load/) next
      count[combo]++
      source[combo] = source[combo] FILENAME "\n"
    }
    END {
      for (combo in count) {
        if (count[combo] > 1) {
          printf "%s\t%d\n", combo, count[combo]
        }
      }
    }
  ' "${files[@]}" 2>/dev/null | sort
}

skhd_report_duplicates() {
  local config="$1"
  local duplicates
  duplicates="$(skhd_duplicate_bindings "$config")"
  if [[ -z "$duplicates" ]]; then
    echo "skhd duplicates: none"
    return 0
  fi
  echo "skhd duplicates:" >&2
  printf '%s\n' "$duplicates" | sed 's/^/  /' >&2
  return 1
}

skhd_fix_load_line() {
  local config="$1"
  local expected
  expected=$(skhd_expected_load_line)
  mkdir -p "$(dirname "$config")" 2>/dev/null || true

  if [[ -f "$config" ]] && grep -q "barista_shortcuts.conf" "$config"; then
    local tmp
    tmp=$(mktemp)
    awk -v expected="$expected" '/barista_shortcuts\.conf/ { print expected; next } { print }' "$config" > "$tmp"
    mv "$tmp" "$config"
    return 0
  fi

  printf "\n%s\n" "$expected" >> "$config"
}

skhd_generate_shortcuts() {
  local generator="$CONFIG_DIR/helpers/generate_shortcuts.lua"
  if [[ ! -f "$generator" ]]; then
    echo "shortcuts generator not found: $generator" >&2
    return 1
  fi
  if ! command -v lua >/dev/null 2>&1; then
    echo "lua not found; cannot regenerate shortcuts" >&2
    return 1
  fi
  BARISTA_CONFIG_DIR="$CONFIG_DIR" lua "$generator" >/dev/null 2>&1
}

run_doctor() {
  local fix=0
  case "${1:-}" in
    fix|--fix) fix=1 ;;
  esac
  local ok=1
  if ! pgrep -x yabai >/dev/null 2>&1; then
    echo "yabai: not running"
    ok=0
    if (( fix == 1 )) && start_yabai; then
      sleep 0.5
      if pgrep -x yabai >/dev/null 2>&1; then
        echo "yabai: started"
        ok=1
      fi
    fi
  else
    echo "yabai: running"
  fi

  if [[ -z "$SKHD_BIN" ]]; then
    echo "skhd: not installed"
    ok=0
  else
    if ! skhd_running; then
      echo "skhd: not running"
      ok=0
      if (( fix == 1 )) && skhd_start; then
        echo "skhd: started"
      fi
    else
      echo "skhd: running"
    fi

    local pid_count
    pid_count=$(skhd_pid_count)
    if (( pid_count > 1 )); then
      echo "skhd: multiple instances (${pid_count})" >&2
      ok=0
      if (( fix == 1 )); then
        skhd_kill_all
        if skhd_start; then
          echo "skhd: restarted after duplicate cleanup"
        fi
      fi
    fi
  fi

  if [[ -n "$SKHD_BIN" ]]; then
    local skhd_config
    local skhd_shortcuts
    skhd_config=$(skhd_config_path)
    skhd_shortcuts=$(skhd_shortcuts_path)
    echo "skhd config: $skhd_config"
    echo "skhd shortcuts path: $skhd_shortcuts"
    skhd_print_loaded_files "$skhd_config"

    if [[ -f "$skhd_shortcuts" ]] && [[ -s "$skhd_shortcuts" ]]; then
      echo "skhd shortcuts: present"
    else
      echo "skhd shortcuts: missing ($skhd_shortcuts)" >&2
      ok=0
      if (( fix == 1 )) && skhd_generate_shortcuts; then
        echo "skhd shortcuts: regenerated"
      fi
    fi

    if skhd_check_load_line "$skhd_config"; then
      echo "skhd config: load ok"
    else
      ok=0
      if (( fix == 1 )); then
        skhd_fix_load_line "$skhd_config"
        echo "skhd config: load updated"
      fi
    fi

    if ! skhd_report_duplicates "$skhd_config"; then
      ok=0
    fi

    local shortcut_summary missing_targets
    shortcut_summary="$(skhd_shortcut_inventory_summary "$skhd_config")"
    echo "skhd shortcut summary: $shortcut_summary"
    missing_targets="$(summary_value "$shortcut_summary" missing_targets)"
    if [[ "${missing_targets:-0}" != "0" ]]; then
      ok=0
    fi

    local err_log
    err_log=$(skhd_error_log)
    if [[ -s "$err_log" ]] && skhd_error_recent "$err_log"; then
      echo "skhd warnings: recent log entries ($err_log)" >&2
      tail -n 3 "$err_log" | sed 's/^/  /' >&2 || true
      if (( fix == 1 )); then
        skhd_generate_shortcuts || true
        skhd_fix_load_line "$skhd_config" || true
      fi
    fi

    if (( fix == 1 )); then
      if skhd_running; then
        skhd_reload || skhd_restart || true
      else
        skhd_start || true
      fi
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    local current
    if current=$(current_space_index 2>/dev/null); then
      echo "current space: $current"
      if output=$("$YABAI_BIN" -m space --focus "$current" 2>&1); then
        echo "space focus ok"
      elif echo "$output" | grep -q "already focused space"; then
        echo "space focus ok"
      else
        echo "space focus failed (scripting addition likely missing)" >&2
        ok=0
      fi
    else
      echo "unable to query spaces" >&2
      ok=0
    fi
  else
    echo "jq not found; skipping space query" >&2
  fi

  if (( ok == 1 )); then
    echo "doctor: ok"
    return 0
  fi
  return 1
}

command=${1:-}
shift || true

case "$command" in
  status)
    layout=$(current_space_layout 2>/dev/null || echo "unknown")
    current=$(current_space_index 2>/dev/null || echo "unknown")
    echo "layout: $layout"
    echo "current space: $current"
    ;;
  start)
    start_yabai
    ;;
  restart)
    restart_yabai
    ;;
  wm-mode|mode|set-mode)
    wm_mode_command "${1:-}"
    ;;
  app-default-current)
    app_default_current "${1:-}"
    ;;
  app-default)
    app_default_command "$@"
    ;;
  balance)
    run_space_command --balance
    ;;
  space-rotate|rotate)
    run_space_command --rotate 90
    ;;
  mirror)
    run_space_command --mirror x-axis
    ;;
  space-mirror-x)
    run_space_command --mirror x-axis
    ;;
  space-mirror-y)
    run_space_command --mirror y-axis
    ;;
  space-toggle-padding-gap)
    space_toggle_padding_gap
    ;;
  toggle-layout)
    layout=$(current_space_layout)
    case "$layout" in
      bsp) target="stack" ;;
      stack) target="bsp" ;;
      float) target="bsp" ;;
      *) target="bsp" ;;
    esac
    run_space_command --layout "$target"
    ;;
  space-layout)
    layout=${1:-}
    if [[ -z "$layout" ]]; then
      echo "Usage: $0 space-layout <bsp|stack|float>" >&2
      exit 1
    fi
    run_space_command --layout "$layout"
    ;;
  window-toggle-float)
    window_toggle_property float
    ;;
  window-toggle-sticky)
    window_toggle_property sticky
    ;;
  window-toggle-fullscreen)
    window_toggle_property zoom-fullscreen
    ;;
  window-toggle-topmost)
    window_toggle_topmost
    ;;
  window-adopt-space-mode)
    window_adopt_space_mode "${1:-}"
    ;;
  window-center)
    window_center
    ;;
  window-preset-utility)
    window_preset_utility
    ;;
  window-preset-focus)
    window_preset_focus
    ;;
  window-preset-presentation)
    window_preset_presentation
    ;;
  window-preset-tile-here)
    window_preset_tile_here
    ;;
  window-display-next)
    move_window_with_rules --policy adopt_destination --display next
    ;;
  window-display-prev)
    move_window_with_rules --policy adopt_destination --display prev
    ;;
  window-space-next)
    move_window_with_rules --space next
    ;;
  window-space-prev)
    move_window_with_rules --space prev
    ;;
  window-space)
    target=${1:-}
    if [[ -z "$target" ]]; then
      echo "Usage: $0 window-space <index>" >&2
      exit 1
    fi
    move_window_with_rules --space "$target"
    ;;
  window-space-float)
    window_move_to_layout_space float
    ;;
  space-focus-prev-wrap)
    space_focus_wrap prev
    ;;
  space-focus-next-wrap)
    space_focus_wrap next
    ;;
  display-focus-prev-wrap)
    display_focus_wrap prev
    ;;
  display-focus-next-wrap)
    display_focus_wrap next
    ;;
  window-focus-west)
    window_focus_direction west
    ;;
  window-focus-south)
    window_focus_direction south
    ;;
  window-focus-north)
    window_focus_direction north
    ;;
  window-focus-east)
    window_focus_direction east
    ;;
  window-swap-west)
    window_swap_direction west
    ;;
  window-swap-south)
    window_swap_direction south
    ;;
  window-swap-north)
    window_swap_direction north
    ;;
  window-swap-east)
    window_swap_direction east
    ;;
  space-prev)
    space_focus_safe prev
    ;;
  space-next)
    space_focus_safe next
    ;;
  space-recent)
    space_focus_safe recent
    ;;
  space-first)
    space_focus_safe first
    ;;
  space-last)
    space_focus_safe last
    ;;
  window-space-prev-wrap)
    window_space_wrap prev
    ;;
  window-space-next-wrap)
    window_space_wrap next
    ;;
  space-focus-app)
    space_focus_app "$@"
    ;;
  shortcuts)
    run_shortcuts_inventory "$@"
    ;;
  rules-audit)
    run_rules_audit "$@"
    ;;
  doctor)
    run_doctor "$@"
    ;;
  *)
    cat <<'USAGE'
Usage: yabai_control.sh <command>

Commands:
  status
  start
  restart
  wm-mode <required|optional|disabled|auto>
  app-default-current <float|tile|unset>
  app-default <list|set <App Name> <float|tile>|unset <App Name>>
  balance
  space-rotate|rotate
  mirror
  space-mirror-x|space-mirror-y
  space-toggle-padding-gap
  toggle-layout
  space-layout <bsp|stack|float>
  window-toggle-float
  window-toggle-sticky
  window-toggle-fullscreen
  window-toggle-topmost
  window-preset-utility|window-preset-focus|window-preset-presentation|window-preset-tile-here
  window-adopt-space-mode [space]
  window-center
  window-display-next|window-display-prev
  window-space-next|window-space-prev
  window-space <index>
  window-space-float
  space-focus-prev-wrap|space-focus-next-wrap
  display-focus-prev-wrap|display-focus-next-wrap
  window-focus-west|window-focus-south|window-focus-north|window-focus-east
  window-swap-west|window-swap-south|window-swap-north|window-swap-east
  space-prev|space-next|space-recent|space-first|space-last
  window-space-prev-wrap|window-space-next-wrap
  space-focus-app <AppName>
  shortcuts [--json]
  rules-audit [--json]
  doctor [--fix]
USAGE
    exit 1
    ;;
 esac
