#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${BARISTA_YABAI_BIN:-${YABAI_BIN:-$(command -v yabai || true)}}"
JQ_BIN="${BARISTA_JQ_BIN:-${JQ_BIN:-$(command -v jq || true)}}"
SKHD_BIN="${SKHD_BIN:-$(command -v skhd || true)}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITER="$SOURCE_DIR/yabai_state.py"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}}"
FRONT_APP_SCRIPT="${BARISTA_FRONT_APP_SCRIPT:-$CONFIG_DIR/plugins/front_app.sh}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$CONFIG_DIR/scripts/front_app_context.sh}"
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-$CONFIG_DIR/scripts/runtime_context.sh}"
YABAI_LABEL="${BARISTA_YABAI_LABEL:-}"
YABAI_LABEL_NEW="com.asmvik.yabai"
YABAI_LABEL_OLD="com.koekeishiya.yabai"
SPACE_FOCUS_TIMEOUT_SEC="${SPACE_FOCUS_TIMEOUT_SEC:-1}"
SPACE_QUERY_TIMEOUT_SEC="${SPACE_QUERY_TIMEOUT_SEC:-1}"
SPACE_FOCUS_LOCK_STALE_SEC="${SPACE_FOCUS_LOCK_STALE_SEC:-2}"
SPACE_FOCUS_LOCK_DIR="${BARISTA_SPACE_FOCUS_LOCK_DIR:-/tmp/yabai_control_space_focus_${UID}.lock}"
SPACE_FOCUS_OSASCRIPT_FALLBACK="${SPACE_FOCUS_OSASCRIPT_FALLBACK:-0}"
REQUESTED_COMMAND="${1:-}"

if [[ -z "$YABAI_BIN" ]]; then
  case "$REQUESTED_COMMAND" in
    shortcuts|wm-mode|mode|set-mode|app-default|app-level|space-policy|space-lock|space-unlock|feature-toggle|workflow-policy)
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

  if [[ -n "${BARISTA_TARGET_SPACE_INDEX:-}" ]]; then
    printf '%s\n' "$BARISTA_TARGET_SPACE_INDEX"
    return 0
  fi
  if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
    focused_window_json | "$JQ_BIN" -er '.space'
    return
  fi

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

  if [[ -n "${BARISTA_TARGET_SPACE_INDEX:-}" ]]; then
    space_layout_for_index "$BARISTA_TARGET_SPACE_INDEX"
    return
  fi

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
  if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
    local display
    display="$(focused_window_json | "$JQ_BIN" -er '.display')" || return 1
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display "$display" | "$JQ_BIN" -r '.[].index'
    return
  fi
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
  if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
    local window_json
    if [[ ! "$BARISTA_TARGET_WINDOW_ID" =~ ^[1-9][0-9]*$ ]]; then
      echo "Invalid target window: $BARISTA_TARGET_WINDOW_ID" >&2
      return 1
    fi
    window_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$BARISTA_TARGET_WINDOW_ID")" || return 1
    if ! printf '%s\n' "$window_json" | "$JQ_BIN" -e \
      --argjson id "$BARISTA_TARGET_WINDOW_ID" --arg app "${BARISTA_TARGET_APP:-}" \
      '.id == $id and ($app == "" or .app == $app)' >/dev/null; then
      echo "The selected window is no longer available; reopen the window menu" >&2
      return 1
    fi
    printf '%s\n' "$window_json"
  else
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window 2>/dev/null || true
  fi
}

run_window_command() {
  if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
    local window_id
    window_id="$(focused_window_id)" || return 1
    [[ -n "$window_id" ]] || return 1
    "$YABAI_BIN" -m window "$window_id" "$@"
  else
    "$YABAI_BIN" -m window "$@"
  fi
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
    | "$JQ_BIN" -er '."is-floating" | select(type == "boolean") | tostring' 2>/dev/null \
    | head -n 1
}

window_is_fullscreen_for_id() {
  local window_id="${1:-}"
  [ -n "$window_id" ] || return 0
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
    | "$JQ_BIN" -er 'select(.id != null) | (."has-fullscreen-zoom" // ."is-native-fullscreen" // false) | tostring' 2>/dev/null \
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
    # Match tiled windows. Auto raises floating windows above that layer again.
    # A Raised app goes back to its level instead of the shared base.
    local app sub_layer="below"
    app="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null \
      | "$JQ_BIN" -r '.app // empty' 2>/dev/null || true)"
    if [ -n "$app" ] && [ "$(rules_sub_layer_for_app "$app" 2>/dev/null)" = "normal" ]; then
      sub_layer="normal"
    fi
    "$YABAI_BIN" -m window "$window_id" --sub-layer "$sub_layer" || return 1
    if window_is_topmost_for_id "$window_id"; then
      echo "This app is keeping its window on top. Turn off its pin or reopen the app." >&2
      return 1
    fi
  fi
}

set_window_floating_for_id() {
  local window_id="${1:-}"
  local desired="${2:-}"
  local current

  [ -n "$window_id" ] || return 0
  [ -n "$desired" ] || return 0

  current="$(window_is_floating_for_id "$window_id")" || return 1
  if [[ "$desired" == "true" && "$current" != "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle float || return 1
  elif [[ "$desired" == "false" && "$current" == "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle float || return 1
  fi
  [[ "$(window_is_floating_for_id "$window_id")" == "$desired" ]] || {
    echo "Window $window_id did not adopt the requested floating state" >&2
    return 1
  }
}

set_window_fullscreen_for_id() {
  local window_id="${1:-}"
  local desired="${2:-}"
  local current

  [ -n "$window_id" ] || return 0
  [ -n "$desired" ] || return 0

  current="$(window_is_fullscreen_for_id "$window_id")" || return 1
  if [[ "$desired" == "true" && "$current" != "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle zoom-fullscreen || return 1
  elif [[ "$desired" == "false" && "$current" == "true" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle zoom-fullscreen || return 1
  fi
  [[ "$(window_is_fullscreen_for_id "$window_id")" == "$desired" ]] || {
    echo "Window $window_id did not adopt the requested fullscreen state" >&2
    return 1
  }
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

run_space_mutation() {
  if [[ -n "${BARISTA_TARGET_SPACE_INDEX:-}" ]]; then
    local target_json
    [[ "$BARISTA_TARGET_SPACE_INDEX" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid target space" >&2; return 1; }
    target_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --space "$BARISTA_TARGET_SPACE_INDEX")" || return 1
    require_jq
    if ! printf '%s\n' "$target_json" | "$JQ_BIN" -e --argjson index "$BARISTA_TARGET_SPACE_INDEX" \
      --arg id "${BARISTA_TARGET_SPACE_ID:-}" '.index == $index and ($id == "" or (.id | tostring) == $id)' >/dev/null; then
      echo "The selected space changed; reopen the space menu" >&2
      return 1
    fi
    "$YABAI_BIN" -m space "$BARISTA_TARGET_SPACE_INDEX" "$@"
  else
    "$YABAI_BIN" -m space "$@"
  fi
}

run_space_command() {
  run_space_mutation "$@"
  refresh_space_state
  refresh_front_app_state
}

apply_space_layout() {
  BARISTA_CONFIG_DIR="$CONFIG_DIR" BARISTA_STATE_FILE="$STATE_FILE" \
    YABAI_BIN="$YABAI_BIN" JQ_BIN="$JQ_BIN" SKETCHYBAR_BIN="$SKETCHYBAR_BIN" \
    "$SOURCE_DIR/../plugins/set_space_mode.sh" "${BARISTA_TARGET_SPACE_INDEX:-current}" "$1" || return 1
  refresh_front_app_state
}

space_toggle_padding_gap() {
  run_space_mutation --toggle padding
  run_space_mutation --toggle gap
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
  local target_layout

  [ -n "$window_id" ] || return 0
  [ -n "$target_space" ] || return 0

  target_layout="$(space_layout_for_index "$target_space")"
  case "$target_layout" in
    float)
      set_window_floating_for_id "$window_id" true || return 1
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
  local target_layout

  [ -n "$window_id" ] || return 0
  [ -n "$target_space" ] || return 0

  target_layout="$(space_layout_for_index "$target_space")"
  case "$target_layout" in
    float)
      set_window_floating_for_id "$window_id" true || return 1
      ;;
    bsp|stack)
      set_window_floating_for_id "$window_id" false || return 1
      ;;
    *) echo "Cannot determine the layout for Space $target_space" >&2; return 1 ;;
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
  focused_json="$(focused_window_json)" || return 1
  window_id_from_json "$focused_json"
}

move_window_with_rules() {
  local policy="${BARISTA_WINDOW_MOVE_POLICY:-}"
  if [[ -z "$policy" && -n "$JQ_BIN" && -f "$STATE_FILE" ]]; then
    policy="$("$JQ_BIN" -r '.spaces.window_move_policy // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  policy="${policy:-preserve}"

  if [[ "${1:-}" == "--policy" ]]; then
    policy="${2:-preserve}"
    shift 2
  fi

  if [[ -z "$JQ_BIN" ]]; then
    run_window_command "$@"
    return
  fi

  local focused_json window_id target_space
  focused_json="$(focused_window_json)" || return 1
  window_id="$(window_id_from_json "$focused_json")"

  if [[ -z "$window_id" ]]; then
    run_window_command "$@"
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

space_focus_index() {
  local target="${1:-}"
  if [[ ! "$target" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 space-focus <positive-index>" >&2
    return 1
  fi

  if ! acquire_space_focus_lock; then
    return 0
  fi

  local rc=0
  run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" "$YABAI_BIN" -m space --focus "$target" >/dev/null 2>&1 || rc=$?
  release_space_focus_lock

  if (( rc == 0 || rc == 124 )); then
    return 0
  fi

  echo "space focus failed for index ${target} (scripting addition likely missing)" >&2
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

  if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
    run_window_command --focus "$direction" || return 1
    refresh_space_state
    refresh_front_app_state
    return 0
  fi

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

  run_window_command --swap "$direction" || rc=$?
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
  run_window_command --grid 4:4:1:1:2:2
  refresh_front_app_state
}

window_focus_next_wrap() {
  if run_window_command --focus next || run_window_command --focus first; then
    refresh_space_state
    refresh_front_app_state
    return 0
  fi
  return 1
}

window_insert_direction() {
  run_window_command --insert "$1"
  refresh_front_app_state
}

window_toggle_property() {
  local property="${1:-}"
  [ -n "$property" ] || return 1
  run_window_command --toggle "$property"
  refresh_front_app_state
}

window_toggle_topmost() {
  local window_id
  require_jq
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || { echo "No window available." >&2; return 1; }

  if window_is_topmost_for_id "$window_id"; then
    clear_window_topmost_for_id "$window_id" || return 1
  else
    "$YABAI_BIN" -m window "$window_id" --sub-layer above || return 1
    if ! window_is_topmost_for_id "$window_id"; then
      echo "Always on top did not turn on. Reopen the menu and try again." >&2
      return 1
    fi
  fi
  refresh_front_app_state
}

window_preset_utility() {
  local window_id
  window_id="$(focused_window_id)"
  [[ -n "$window_id" ]] || return 1

  set_window_fullscreen_for_id "$window_id" false
  set_window_floating_for_id "$window_id" true
  clear_window_topmost_for_id "$window_id"
  "$YABAI_BIN" -m window "$window_id" --grid 4:4:1:1:2:2
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
  "$YABAI_BIN" -m space "$target_space" --balance
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

state_app_command() {
  local py
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 required to update app defaults" >&2; return 1; }
  "$py" "$STATE_WRITER" "$STATE_FILE" "$@"
}

rules_json() {
  [[ -n "${YABAI_BIN:-}" ]] || { echo "yabai is required to apply app defaults" >&2; return 1; }
  require_jq
  local rules
  rules="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m rule --list)" || return 1
  printf '%s\n' "$rules" | "$JQ_BIN" -e 'type == "array"' >/dev/null || return 1
  printf '%s\n' "$rules"
}

check_rule_label_owner() {
  local label="$1" app_regex="$2" rules="$3"
  if printf '%s\n' "$rules" | "$JQ_BIN" -e --arg label "$label" --arg app "$app_regex" \
    'any(.[]; .label == $label and .app != $app)' >/dev/null; then
    echo "App default label belongs to another app: $label" >&2
    return 1
  fi
}

remove_yabai_rule_label() {
  local label="$1" app_regex="$2" rules
  rules="$(rules_json)" || return 1
  check_rule_label_owner "$label" "$app_regex" "$rules" || return 1
  if printf '%s\n' "$rules" | "$JQ_BIN" -e --arg label "$label" 'any(.[]; .label == $label)' >/dev/null; then
    "$YABAI_BIN" -m rule --remove "$label" || return 1
    rules="$(rules_json)" || return 1
    if ! printf '%s\n' "$rules" | "$JQ_BIN" -e --arg label "$label" 'all(.[]; .label != $label)' >/dev/null; then
      echo "App default rule removal could not be verified: $label" >&2
      return 1
    fi
  fi
}

install_yabai_app_rule() {
  local app="$1" mode="$2" app_regex label manage rules
  app_regex="$(regex_escape_app_name "$app")"
  label="$(rule_label_for_app "$app")"
  state_app_command app-check || return 1
  rules="$(rules_json)" || return 1
  check_rule_label_owner "$label" "$app_regex" "$rules" || return 1
  manage=off
  [[ "$mode" != "tile" ]] || manage=on
  # Yabai replaces a same-label rule only after parsing the new rule. Keeping
  # replacement in one command preserves the old rule if the new add fails.
  # Stacking is left to app levels (app-level), so floating never pins an app above others.
  "$YABAI_BIN" -m rule --add label="$label" app="$app_regex" manage="$manage" || return 1
  rules="$(rules_json)" || return 1
  if ! printf '%s\n' "$rules" | "$JQ_BIN" -e --arg label "$label" --arg app "$app_regex" --arg mode "$mode" \
    'any(.[]; .label == $label and .app == $app and .manage == ($mode == "tile") and (.["sub-layer"] // "") == "")' >/dev/null; then
    echo "App default rule could not be verified; saved state was not changed" >&2
    return 1
  fi
  if ! state_app_command app-default "$app" "$mode" "$app_regex" "$label"; then
    echo "App default is active for $app, but the choice could not be saved" >&2
    return 1
  fi
}

apply_current_window_default() {
  local mode="$1" window_id="$2" app="$3" window_json floating desired layout space
  [[ -n "$window_id" ]] || return 0
  window_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window "$window_id")" || return 1
  if ! printf '%s\n' "$window_json" | "$JQ_BIN" -e --argjson id "$window_id" --arg app "$app" \
    '.id == $id and .app == $app' >/dev/null; then
    echo "App default was saved; the original window is no longer available" >&2
    return 1
  fi
  floating="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.["is-floating"]')"
  desired=true
  if [[ "$mode" == "tile" ]]; then
    space="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.space')"
    layout="$(space_layout_for_index "$space")" || return 1
    if [[ "$layout" == "float" ]]; then
      echo "App default saved; Space $space is floating, so this window stays floating"
      return 0
    fi
    [[ "$layout" == "bsp" || "$layout" == "stack" ]] || return 1
    desired=false
  fi
  if [[ "$floating" != "$desired" ]]; then
    "$YABAI_BIN" -m window "$window_id" --toggle float || return 1
  fi
  if [[ "$(window_is_floating_for_id "$window_id")" != "$desired" ]]; then
    echo "App default was saved, but window $window_id did not adopt it" >&2
    return 1
  fi
}

app_default_set() {
  local app="$1" mode="$2"
  [[ -n "$app" && -n "$mode" ]] || { echo "Usage: $0 app-default set <App Name> <float|tile>" >&2; return 1; }
  mode="$(normalize_app_default_mode "$mode")"
  case "$mode" in
    float|tile) ;;
    *) echo "Usage: $0 app-default set <App Name> <float|tile>" >&2; return 1 ;;
  esac
  install_yabai_app_rule "$app" "$mode" || return 1
  echo "app default: $app -> $mode (new windows)"
}

app_default_unset() {
  local app="$1" label app_regex
  [[ -n "$app" ]] || { echo "Usage: $0 app-default unset <App Name>" >&2; return 1; }
  label="$(rule_label_for_app "$app")"
  app_regex="$(regex_escape_app_name "$app")"
  state_app_command app-check || return 1
  remove_yabai_rule_label "$label" "$app_regex" || return 1
  if ! state_app_command app-unset "$app"; then
    echo "App default rule was removed for $app, but saved state could not be updated" >&2
    return 1
  fi
  echo "Barista app default removed: $app; other Yabai rules still apply"
}

app_default_current() {
  local mode app window_json window_id
  mode="$(normalize_app_default_mode "${1:-}")"
  case "$mode" in
    float|tile|unset) ;;
    *) echo "Usage: $0 app-default-current <float|tile|unset>" >&2; return 1 ;;
  esac
  window_json="$(focused_window_json)" || return 1
  window_id="$(window_id_from_json "$window_json")"
  app="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.app // empty')"
  if [[ -z "$app" ]]; then
    app="$(current_app_name)" || return 1
  fi
  if [[ "$mode" == "unset" ]]; then
    app_default_unset "$app" || return 1
  else
    app_default_set "$app" "$mode" || return 1
    apply_current_window_default "$mode" "$window_id" "$app" || return 1
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

# App levels: where an app's windows stack. Windows on one sub-layer reorder
# by focus; a higher one always stays above a lower one. yabairc's
# barista-level-base rule puts every window on the tiled windows' layer.
level_rule_label_for_app() {
  echo "barista-level-$(slugify_app_name "$1")"
}

normalize_app_level() {
  local level
  level="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$level" in
    normal|shared) echo "normal" ;;
    raised|high) echo "raised" ;;
    top|topmost|always-on-top) echo "top" ;;
    unset|remove|clear|rules|none) echo "unset" ;;
    *) echo "$level" ;;
  esac
}

sub_layer_for_level() {
  case "$1" in
    normal) echo "below" ;;
    raised) echo "normal" ;;
    top) echo "above" ;;
    *) return 1 ;;
  esac
}

# The sub-layer yabai's remaining rules give an app: the last matching rule
# that sets one wins, as yabai combines them; none means auto.
rules_sub_layer_for_app() {
  local app="$1" rules
  rules="$(rules_json)" || return 1
  printf '%s\n' "$rules" | "$JQ_BIN" -r --arg app "$app" '
    [.[] | select((.["sub-layer"] // "") != "" and (.title // "") == ""
                  and ((.app // "") as $re | $re != "" and (try ($app | test($re)) catch false)))]
    | (last | .["sub-layer"]) // "auto"'
}

# Rules reach only new windows; open ones are moved here.
apply_sub_layer_to_app_windows() {
  local app="$1" sub_layer="$2" windows id failed=0
  windows="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows)" || return 1
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    "$YABAI_BIN" -m window "$id" --sub-layer "$sub_layer" >/dev/null 2>&1 || failed=1
  done < <(printf '%s\n' "$windows" | "$JQ_BIN" -r --arg app "$app" \
    '.[] | select(.app == $app and .subrole == "AXStandardWindow") | .id')
  return "$failed"
}

install_yabai_level_rule() {
  local app="$1" level="$2" app_regex label sub_layer rules
  app_regex="$(regex_escape_app_name "$app")"
  label="$(level_rule_label_for_app "$app")"
  sub_layer="$(sub_layer_for_level "$level")" || return 1
  state_app_command level-check || return 1
  rules="$(rules_json)" || return 1
  check_rule_label_owner "$label" "$app_regex" "$rules" || return 1
  "$YABAI_BIN" -m rule --add label="$label" app="$app_regex" sub-layer="$sub_layer" || return 1
  rules="$(rules_json)" || return 1
  if ! printf '%s\n' "$rules" | "$JQ_BIN" -e --arg label "$label" --arg app "$app_regex" --arg layer "$sub_layer" \
    'any(.[]; .label == $label and .app == $app and .["sub-layer"] == $layer)' >/dev/null; then
    echo "App level rule could not be verified; saved state was not changed" >&2
    return 1
  fi
  if ! state_app_command app-level "$app" "$level" "$app_regex" "$label"; then
    echo "App level is active for $app, but the choice could not be saved" >&2
    return 1
  fi
}

app_level_set() {
  local app="$1" level
  level="$(normalize_app_level "${2:-}")"
  case "$level" in
    normal|raised|top) ;;
    *) echo "Usage: $0 app-level set <App Name> <normal|raised|top>" >&2; return 1 ;;
  esac
  [[ -n "$app" ]] || { echo "Usage: $0 app-level set <App Name> <normal|raised|top>" >&2; return 1; }
  require_jq
  install_yabai_level_rule "$app" "$level" || return 1
  if ! apply_sub_layer_to_app_windows "$app" "$(sub_layer_for_level "$level")"; then
    echo "App level saved for $app; some open windows did not move and will on reopen" >&2
  fi
  echo "app level: $app -> $level"
}

app_level_unset() {
  local app="$1" label app_regex layer
  [[ -n "$app" ]] || { echo "Usage: $0 app-level unset <App Name>" >&2; return 1; }
  require_jq
  label="$(level_rule_label_for_app "$app")"
  app_regex="$(regex_escape_app_name "$app")"
  state_app_command level-check || return 1
  remove_yabai_rule_label "$label" "$app_regex" || return 1
  if ! state_app_command level-unset "$app"; then
    echo "App level rule was removed for $app, but saved state could not be updated" >&2
    return 1
  fi
  layer="$(rules_sub_layer_for_app "$app")" || return 1
  apply_sub_layer_to_app_windows "$app" "$layer" || true
  echo "Barista app level removed: $app; Yabai rules give it $layer"
}

app_level_current() {
  local level window_json app
  level="$(normalize_app_level "${1:-}")"
  case "$level" in
    normal|raised|top|unset) ;;
    *) echo "Usage: $0 app-level-current <normal|raised|top|unset>" >&2; return 1 ;;
  esac
  window_json="$(focused_window_json)" || return 1
  app="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.app // empty')"
  [[ -n "$app" ]] || app="$(current_app_name)" || return 1
  if [[ "$level" == "unset" ]]; then
    app_level_unset "$app" || return 1
  else
    app_level_set "$app" "$level" || return 1
  fi
  refresh_front_app_state
}

app_level_list() {
  local py
  py="$(python3_bin)"
  if [[ -z "$py" || ! -f "$STATE_FILE" ]]; then
    echo "no app levels"
    return 0
  fi
  "$py" - "$STATE_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {}
levels = (data if isinstance(data, dict) else {}).get('window_levels') or {}
if not levels:
    print('no app levels')
else:
    for app in sorted(levels):
        rec = levels[app] if isinstance(levels[app], dict) else {}
        print(f"{app}: {rec.get('level', 'unknown')}")
PY
}

app_level_command() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    set)
      if (( $# < 2 )); then
        echo "Usage: $0 app-level set <App Name> <normal|raised|top>" >&2
        return 1
      fi
      local level="${!#}"
      local app="${*:1:$#-1}"
      app_level_set "$app" "$level"
      ;;
    unset|remove|clear)
      app_level_unset "$*"
      ;;
    list|ls|"")
      app_level_list
      ;;
    *)
      echo "Usage: $0 app-level <list|set <App Name> <normal|raised|top>|unset <App Name>>" >&2
      return 1
      ;;
  esac
}

space_action_script_path() {
  if [[ -x "$SOURCE_DIR/space_action.sh" ]]; then
    printf '%s' "$SOURCE_DIR/space_action.sh"
    return 0
  fi
  if [[ -x "$CONFIG_DIR/scripts/space_action.sh" ]]; then
    printf '%s' "$CONFIG_DIR/scripts/space_action.sh"
    return 0
  fi
  echo "space_action.sh not found" >&2
  return 1
}

run_space_action() {
  local script_path
  script_path="$(space_action_script_path)" || return 1
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$YABAI_BIN" JQ_BIN="$JQ_BIN" SKETCHYBAR_BIN="$SKETCHYBAR_BIN" \
    "$script_path" "$@"
}

space_prune_command() {
  local dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        dry_run=1
        ;;
      *)
        echo "Usage: $0 space-prune [--dry-run]" >&2
        return 1
        ;;
    esac
    shift || true
  done
  require_jq
  local spaces_json op="space-prune"
  spaces_json="$(all_spaces_json)" || return 1
  if (( dry_run == 1 )); then
    op="space-prune-check"
  fi
  state_app_command "$op" "$spaces_json"
}

space_policy_command() {
  local py
  py="$(python3_bin)"
  [[ -n "$py" ]] || { echo "python3 required to inspect/update space policy" >&2; return 1; }
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list|ls|--json|"")
      local as_json=0
      [[ "$sub" == "--json" || "${1:-}" == "--json" ]] && as_json=1
      "$py" - "$STATE_FILE" "$as_json" <<'PY'
import json, sys
path = sys.argv[1]
as_json = sys.argv[2] == "1"
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
spaces = (data.get("spaces") if isinstance(data, dict) else {}) or {}
if not isinstance(spaces, dict):
    spaces = {}
locked = spaces.get("locked_spaces", {})
if isinstance(locked, dict):
    locked_list = sorted(str(k) for k, v in locked.items() if v)
elif isinstance(locked, list):
    locked_list = sorted(str(k) for k in locked if str(k))
else:
    locked_list = []
payload = {
    "creator_mode": spaces.get("creator_mode", "per_display"),
    "right_click_close": spaces.get("right_click_close", "confirm"),
    "reorder_mode": spaces.get("reorder_mode", "menu"),
    "max_spaces_per_display": spaces.get("max_spaces_per_display", 8),
    "min_spaces_per_display": spaces.get("min_spaces_per_display", 1),
    "destroy_non_empty_policy": spaces.get("destroy_non_empty_policy", "allow"),
    "new_space_layout": spaces.get("new_space_layout", "default"),
    "window_move_policy": spaces.get("window_move_policy", "preserve"),
    "locked_spaces": locked_list,
}
if as_json:
    print(json.dumps(payload, indent=2))
else:
    for k, v in payload.items():
        if isinstance(v, list):
            print(f"{k}: {', '.join(v) if v else '(none)'}")
        else:
            print(f"{k}: {v}")
PY
      ;;
    get)
      local key="${1:-}"
      [[ -n "$key" ]] || { echo "Usage: $0 space-policy get <key>" >&2; return 1; }
      "$py" - "$STATE_FILE" "$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
defaults = {
    "creator_mode": "per_display",
    "right_click_close": "confirm",
    "reorder_mode": "menu",
    "max_spaces_per_display": 8,
    "min_spaces_per_display": 1,
    "destroy_non_empty_policy": "allow",
    "new_space_layout": "default",
    "window_move_policy": "preserve",
    "locked_spaces": [],
}
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
spaces = (data.get("spaces") if isinstance(data, dict) else {}) or {}
val = spaces.get(key, defaults.get(key))
if isinstance(val, (dict, list)):
    print(json.dumps(val))
elif val is not None:
    print(val)
else:
    sys.exit(1)
PY
      ;;
    set)
      local key="${1:-}" val="${2:-}"
      [[ -n "$key" && -n "$val" ]] || { echo "Usage: $0 space-policy set <key> <value>" >&2; return 1; }
      state_app_command space-policy "$key" "$val"
      ;;
    *)
      if [[ $# -ge 1 ]]; then
        state_app_command space-policy "$sub" "$1"
      else
        echo "Usage: $0 space-policy [list [--json]|get <key>|set <key> <value>]" >&2
        return 1
      fi
      ;;
  esac
}

status_json_command() {
  require_jq
  local spaces_json="[]" windows_json="[]" state_json="{}"
  spaces_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces 2>/dev/null || printf '[]')"
  windows_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows 2>/dev/null || printf '[]')"
  if [[ -f "$STATE_FILE" ]]; then
    state_json="$(cat "$STATE_FILE" 2>/dev/null || printf '{}')"
  fi
  local yabai_up="false" skhd_up="false"
  pgrep -x yabai >/dev/null 2>&1 && yabai_up="true"
  pgrep -x skhd >/dev/null 2>&1 && skhd_up="true"
  "$JQ_BIN" -n \
    --argjson spaces "$spaces_json" \
    --argjson windows "$windows_json" \
    --argjson state "$state_json" \
    --argjson yabai_running "$yabai_up" \
    --argjson skhd_running "$skhd_up" '
    ($spaces | map(select(."has-focus" == true))[0] // $spaces[0] // null) as $cur_space
    | ($windows | map(select(."has-focus" == true))[0] // null) as $cur_win
    | ($state.spaces // {}) as $sp_cfg
    | ($sp_cfg.locked_spaces // {}) as $locked_raw
    | (if ($locked_raw | type) == "array" then ($locked_raw | map(tostring))
       elif ($locked_raw | type) == "object" then ([ $locked_raw | to_entries[] | select(.value == true) | .key ])
       else [] end) as $locked_list
    | {
        yabai_running: $yabai_running,
        skhd_running: $skhd_running,
        window_manager_mode: ($state.modes.window_manager // "auto"),
        runtime_backend: ($state.modes.runtime_backend // "auto"),
        yabai_shortcuts_enabled: ($state.toggles.yabai_shortcuts // true),
        current_space: (if $cur_space == null then null else {
          index: $cur_space.index,
          id: $cur_space.id,
          uuid: ($cur_space.uuid // ""),
          display: $cur_space.display,
          layout: $cur_space.type,
          saved_mode: (($state.space_modes_by_uuid[$cur_space.uuid // ""] // $state.space_modes[($cur_space.index | tostring)]) // null),
          is_native_fullscreen: ($cur_space."is-native-fullscreen" // false),
          window_count: (($cur_space.windows // []) | length)
        } end),
        current_window: (if $cur_win == null then null else {
          id: $cur_win.id,
          app: $cur_win.app,
          title: ($cur_win.title // ""),
          space: $cur_win.space,
          display: $cur_win.display,
          is_floating: ($cur_win."is-floating" // false),
          is_sticky: ($cur_win."is-sticky" // false),
          has_fullscreen_zoom: ($cur_win."has-fullscreen-zoom" // false),
          layer: ($cur_win.layer // "normal"),
          sub_layer: ($cur_win."sub-layer" // "normal"),
          app_default: (($state.window_defaults.apps[$cur_win.app].mode) // null)
        } end),
        space_policies: {
          creator_mode: ($sp_cfg.creator_mode // "per_display"),
          right_click_close: ($sp_cfg.right_click_close // "confirm"),
          reorder_mode: ($sp_cfg.reorder_mode // "menu"),
          max_spaces_per_display: ($sp_cfg.max_spaces_per_display // 8),
          min_spaces_per_display: ($sp_cfg.min_spaces_per_display // 1),
          destroy_non_empty_policy: ($sp_cfg.destroy_non_empty_policy // "allow"),
          new_space_layout: ($sp_cfg.new_space_layout // "default"),
          window_move_policy: ($sp_cfg.window_move_policy // "preserve"),
          locked_spaces: $locked_list
        },
        counts: {
          spaces: ($spaces | length),
          windows: ($windows | length),
          saved_space_modes: (($state.space_modes // {}) | length),
          saved_uuid_modes: (($state.space_modes_by_uuid // {}) | length),
          app_defaults: (($state.window_defaults.apps // {}) | length)
        }
      }
  '
}

spaces_inventory_command() {
  require_jq
  local as_json=0
  [[ "${1:-}" == "--json" ]] && as_json=1
  local spaces_json state_json="{}"
  spaces_json="$(all_spaces_json)" || return 1
  if [[ -f "$STATE_FILE" ]]; then
    state_json="$(cat "$STATE_FILE" 2>/dev/null || printf '{}')"
  fi
  if (( as_json == 1 )); then
    printf '%s\n' "$spaces_json" | "$JQ_BIN" --argjson state "$state_json" '
      (($state.spaces.locked_spaces // {}) | if type == "array" then map(tostring) elif type == "object" then [to_entries[] | select(.value == true) | .key] else [] end) as $locked
      | map(
          (.index | tostring) as $idx
          | (.uuid // "") as $uuid
          | {
              index: .index,
              id: .id,
              uuid: $uuid,
              display: .display,
              layout: .type,
              saved_mode: (($state.space_modes_by_uuid[$uuid] // $state.space_modes[$idx]) // null),
              has_focus: (."has-focus" // false),
              is_visible: (."is-visible" // false),
              is_native_fullscreen: (."is-native-fullscreen" // false),
              locked: (($locked | index($idx) != null) or ($uuid != "" and ($locked | index($uuid) != null))),
              window_count: ((.windows // []) | length),
              windows: (.windows // [])
            }
        )
    '
  else
    printf '%s\n' "$spaces_json" | "$JQ_BIN" -r --argjson state "$state_json" '
      (($state.spaces.locked_spaces // {}) | if type == "array" then map(tostring) elif type == "object" then [to_entries[] | select(.value == true) | .key] else [] end) as $locked
      | .[]
      | (.index | tostring) as $idx
      | (.uuid // "") as $uuid
      | (($locked | index($idx) != null) or ($uuid != "" and ($locked | index($uuid) != null))) as $is_locked
      | "space \($idx) (display \(.display)): layout=\(.type) saved=\(($state.space_modes_by_uuid[$uuid] // $state.space_modes[$idx]) // "none") windows=\((.windows // []) | length)\(if ."has-focus" then " [focused]" else "" end)\(if $is_locked then " [locked]" else "" end)"
    '
  fi
}

windows_inventory_command() {
  require_jq
  local as_json=0
  [[ "${1:-}" == "--json" ]] && as_json=1
  local windows_json state_json="{}"
  windows_json="$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows 2>/dev/null)" || return 1
  if [[ -f "$STATE_FILE" ]]; then
    state_json="$(cat "$STATE_FILE" 2>/dev/null || printf '{}')"
  fi
  if (( as_json == 1 )); then
    printf '%s\n' "$windows_json" | "$JQ_BIN" --argjson state "$state_json" '
      map({
        id: .id,
        app: .app,
        title: (.title // ""),
        space: .space,
        display: .display,
        has_focus: (."has-focus" // false),
        is_floating: (."is-floating" // false),
        is_sticky: (."is-sticky" // false),
        is_minimized: (."is-minimized" // false),
        has_fullscreen_zoom: (."has-fullscreen-zoom" // false),
        layer: (.layer // "normal"),
        sub_layer: (."sub-layer" // "normal"),
        app_default: (($state.window_defaults.apps[.app].mode) // null)
      })
    '
  else
    printf '%s\n' "$windows_json" | "$JQ_BIN" -r --argjson state "$state_json" '
      .[]
      | "window \(.id): app=\(.app) space=\(.space) display=\(.display) floating=\(."is-floating" // false) sub_layer=\(."sub-layer" // "normal") default=\(($state.window_defaults.apps[.app].mode) // "none")\(if ."has-focus" then " [focused]" else "" end)"
    '
  fi
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
  {"label":"Mesen","app":"^(Mesen|Mesen2.*)$","sub_layer":"below"},
  {"label":"Yaze","app":"^Yaze$","sub_layer":"below"},
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

def expected_sub_layer(item):
    return item.get("sub_layer") or "normal"

def is_expected_unmanaged_rule(rule, item):
    return (
        rule.get("manage") is False
        and rule.get("sub-layer") == expected_sub_layer(item)
    )

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
            "message": f"missing expected unmanaged rule: {item.get('label')}",
        })
        continue
    if not any(is_expected_unmanaged_rule(rule, item) for rule in matching):
        layer = expected_sub_layer(item)
        findings.append({
            "severity": "error",
            "type": "rule-without-normal",
            "label": item.get("label"),
            "app": item.get("app"),
            "message": f"expected rule is not manage=off sub-layer={layer}: {item.get('label')}",
        })

expected_unmanaged_rules = [
    (rule, item)
    for item in expected
    for rule in rules
    if rule_matches_expected(rule, item) and is_expected_unmanaged_rule(rule, item)
]
for window in windows:
    if window.get("is-minimized") is True:
        continue
    sub_layer = window.get("sub-layer") or ""
    layer = window.get("layer") or ""
    if sub_layer == "above" or layer == "above":
        findings.append({
            "severity": "warn" if layer == "above" else "info",
            "type": "app-topmost" if layer == "above" else "manual-topmost",
            "id": window.get("id"),
            "app": window.get("app", ""),
            "title": window.get("title", ""),
            "message": ("app-owned pin: Yabai sub-layer cannot clear it; turn off the app pin or reopen the app"
                        if layer == "above" else "window is manually topmost/above"),
        })
    matching_expected = [
        (rule, item)
        for rule, item in expected_unmanaged_rules
        if window_matches_rule(window, rule)
    ]
    if matching_expected:
        allowed_layers = {
            expected_sub_layer(item) for _, item in matching_expected
        } | {"auto", "above"}
        if sub_layer not in allowed_layers:
            expected_layers = "/".join(sorted(
                {expected_sub_layer(item) for _, item in matching_expected}
            ))
            findings.append({
                "severity": "warn",
                "type": "live-policy-mismatch",
                "id": window.get("id"),
                "app": window.get("app", ""),
                "title": window.get("title", ""),
                "sub_layer": sub_layer,
                "message": f"live unmanaged utility window is not {expected_layers}",
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
    if not app or any(
        window_matches_rule(window, rule)
        for rule, _ in expected_unmanaged_rules
    ):
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
  local fix=0 probe_focus=0
  while (( $# > 0 )); do
    case "$1" in
      fix|--fix) fix=1; probe_focus=1 ;;
      --probe-focus) probe_focus=1 ;;
      *) echo "Usage: $0 doctor [--fix] [--probe-focus]" >&2; return 1 ;;
    esac
    shift
  done
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

  if [[ -n "$JQ_BIN" ]]; then
    local current
    if current=$(current_space_index 2>/dev/null); then
      echo "current space: $current"
      if (( probe_focus == 0 )); then
        echo "space focus: not probed (read-only; use doctor --probe-focus)"
      else
        if output=$("$YABAI_BIN" -m space --focus "$current" 2>&1); then
          echo "space focus ok"
        elif echo "$output" | grep -q "already focused space"; then
          echo "space focus ok"
        else
          echo "space focus failed (scripting addition likely missing)" >&2
          ok=0
        fi
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

window_zoom_master() {
  local win_json cur_id cur_space
  win_json="$(focused_window_json)" || return 1
  cur_id="$(printf '%s\n' "$win_json" | "$JQ_BIN" -r '.id // empty')"
  cur_space="$(printf '%s\n' "$win_json" | "$JQ_BIN" -r '.space // empty')"
  [[ -n "$cur_id" && -n "$cur_space" ]] || return 1

  local master_id
  master_id="$("$YABAI_BIN" -m query --windows --space "$cur_space" 2>/dev/null | "$JQ_BIN" -r '
    [ .[] | select((."is-floating" // false) == false and (."is-minimized" // false) == false and (."is-hidden" // false) == false) ]
    | sort_by(.frame.x // 0, .frame.y // 0, .id)
    | .[0].id // empty
  ' 2>/dev/null || true)"
  [[ -n "$master_id" ]] || return 0

  local state_file="${BARISTA_MASTER_SWAP_DIR:-${TMPDIR:-/tmp}}/barista_master_swap_${UID}_${cur_space}"
  if [[ "$cur_id" == "$master_id" ]]; then
    if [[ -r "$state_file" ]]; then
      local prev_id
      prev_id="$(cat "$state_file" 2>/dev/null || true)"
      if [[ -n "$prev_id" && "$prev_id" != "$cur_id" ]]; then
        if "$YABAI_BIN" -m window "$cur_id" --swap "$prev_id" 2>/dev/null; then
          rm -f "$state_file"
          "$YABAI_BIN" -m window --focus "$cur_id" 2>/dev/null || true
          refresh_front_app_state
          return 0
        fi
      fi
    fi
    "$YABAI_BIN" -m window --swap recent 2>/dev/null || "$YABAI_BIN" -m window --swap east 2>/dev/null || true
  else
    printf '%s\n' "$master_id" > "$state_file"
    "$YABAI_BIN" -m window "$cur_id" --swap "$master_id" 2>/dev/null || "$YABAI_BIN" -m window --swap first 2>/dev/null || true
    "$YABAI_BIN" -m window --focus "$cur_id" 2>/dev/null || true
  fi
  refresh_front_app_state
}

window_stack_cycle() {
  local dir="${1:-next}"
  if [[ "$dir" == "prev" ]]; then
    "$YABAI_BIN" -m window --focus stack.prev 2>/dev/null \
      || "$YABAI_BIN" -m window --focus stack.last 2>/dev/null \
      || window_focus_next_wrap
  else
    "$YABAI_BIN" -m window --focus stack.next 2>/dev/null \
      || "$YABAI_BIN" -m window --focus stack.first 2>/dev/null \
      || window_focus_next_wrap
  fi
  refresh_front_app_state
}

window_resize_direction() {
  local dir="${1:-east}"
  local step="${2:-40}"
  case "$step" in ''|*[!0-9]*) step=40 ;; esac
  case "$dir" in
    west|left)
      "$YABAI_BIN" -m window --resize "right:-${step}:0" 2>/dev/null \
        || "$YABAI_BIN" -m window --resize "left:-${step}:0" 2>/dev/null || true
      ;;
    east|right)
      "$YABAI_BIN" -m window --resize "right:${step}:0" 2>/dev/null \
        || "$YABAI_BIN" -m window --resize "left:${step}:0" 2>/dev/null || true
      ;;
    north|up)
      "$YABAI_BIN" -m window --resize "bottom:0:-${step}" 2>/dev/null \
        || "$YABAI_BIN" -m window --resize "top:0:-${step}" 2>/dev/null || true
      ;;
    south|down)
      "$YABAI_BIN" -m window --resize "bottom:0:${step}" 2>/dev/null \
        || "$YABAI_BIN" -m window --resize "top:0:${step}" 2>/dev/null || true
      ;;
    *)
      echo "Usage: $0 window-resize <west|south|north|east> [step]" >&2
      return 1
      ;;
  esac
}

feature_toggle_command() {
  local subcmd="${1:-list}"
  if [[ "$subcmd" == "list" || "$subcmd" == "--json" ]]; then
    local raw
    raw="$(state_app_command feature-check)"
    if [[ "$subcmd" == "--json" || "${2:-}" == "--json" ]]; then
      printf '%s\n' "$raw" | "$JQ_BIN" '.toggles'
    else
      printf '%s\n' "$raw" | "$JQ_BIN" -r '.toggles | to_entries[] | "\(.key): \(if .value then "on" else "off" end)"'
    fi
    return 0
  fi
  local key="$subcmd"
  local val="${2:-toggle}"
  state_app_command feature-toggle "$key" "$val"
}

workflow_policy_command() {
  local subcmd="${1:-list}"
  if [[ "$subcmd" == "list" || "$subcmd" == "--json" ]]; then
    local raw
    raw="$(state_app_command workflow-check)"
    if [[ "$subcmd" == "--json" || "${2:-}" == "--json" ]]; then
      printf '%s\n' "$raw" | "$JQ_BIN" '.workflow'
    else
      printf '%s\n' "$raw" | "$JQ_BIN" -r '
        .workflow | to_entries[] as $sec
        | $sec.value | to_entries[]
        | "\($sec.key).\(.key): \(.value)"
      '
    fi
    return 0
  fi
  if [[ "$subcmd" == "get" ]]; then
    local key="${2:-}"
    [[ -n "$key" ]] || { echo "Usage: $0 workflow-policy get <section.key>" >&2; return 1; }
    state_app_command workflow-check | "$JQ_BIN" -r --arg k "$key" '
      ($k | split(".")) as $parts
      | .workflow[$parts[0]][$parts[1]] // empty
    '
    return 0
  fi
  if [[ "$subcmd" == "set" ]]; then
    shift
  fi
  local key="${1:-}"
  local val="${2:-}"
  [[ -n "$key" ]] || { echo "Usage: $0 workflow-policy [set] <section.key> <value>" >&2; return 1; }
  state_app_command workflow-policy "$key" "$val"
}

command=${1:-}
shift || true

# A menu action is bound to the rendered window. Validate before any mutation,
# including paths that do not otherwise need a focused-window query.
if [[ -n "${BARISTA_TARGET_WINDOW_ID:-}" ]]; then
  case "$command" in
    window-*|app-default-current|app-level-current)
      focused_window_json >/dev/null || exit 1
      ;;
  esac
fi

case "$command" in
  status)
    if [[ "${1:-}" == "--json" ]]; then
      status_json_command
    else
      layout=$(current_space_layout 2>/dev/null || echo "unknown")
      current=$(current_space_index 2>/dev/null || echo "unknown")
      echo "layout: $layout"
      echo "current space: $current"
    fi
    ;;
  spaces)
    spaces_inventory_command "$@"
    ;;
  windows)
    windows_inventory_command "$@"
    ;;
  space-create)
    target_display="active"
    force_arg=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --display)
          shift
          target_display="${1:-active}"
          ;;
        --force|-f)
          force_arg=(--force)
          ;;
        *)
          target_display="$1"
          ;;
      esac
      shift || true
    done
    run_space_action create --display "$target_display" "${force_arg[@]+"${force_arg[@]}"}"
    ;;
  space-destroy)
    target_space=""
    force_arg=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --space)
          shift
          target_space="${1:-}"
          ;;
        --force|-f)
          force_arg=(--force)
          ;;
        *)
          target_space="$1"
          ;;
      esac
      shift || true
    done
    if [[ -z "$target_space" || "$target_space" == "current" ]]; then
      target_space="$(current_space_index)" || exit 1
    fi
    run_space_action destroy --space "$target_space" "${force_arg[@]+"${force_arg[@]}"}"
    ;;
  space-move-left)
    target_space="${1:-}"
    if [[ -z "$target_space" || "$target_space" == "current" ]]; then
      target_space="$(current_space_index)" || exit 1
    fi
    run_space_action move-left --space "$target_space"
    ;;
  space-move-right)
    target_space="${1:-}"
    if [[ -z "$target_space" || "$target_space" == "current" ]]; then
      target_space="$(current_space_index)" || exit 1
    fi
    run_space_action move-right --space "$target_space"
    ;;
  space-move-display-prev)
    target_space="${1:-}"
    if [[ -z "$target_space" || "$target_space" == "current" ]]; then
      target_space="$(current_space_index)" || exit 1
    fi
    run_space_action move-display-prev --space "$target_space"
    ;;
  space-move-display-next)
    target_space="${1:-}"
    if [[ -z "$target_space" || "$target_space" == "current" ]]; then
      target_space="$(current_space_index)" || exit 1
    fi
    run_space_action move-display-next --space "$target_space"
    ;;
  space-prune)
    space_prune_command "$@"
    ;;
  space-lock)
    [[ -n "${1:-}" ]] || { echo "Usage: $0 space-lock <space-index-or-uuid>" >&2; exit 1; }
    state_app_command space-lock "$1"
    ;;
  space-unlock)
    [[ -n "${1:-}" ]] || { echo "Usage: $0 space-unlock <space-index-or-uuid>" >&2; exit 1; }
    state_app_command space-unlock "$1"
    ;;
  space-policy)
    space_policy_command "$@"
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
  app-level-current)
    app_level_current "${1:-}"
    ;;
  app-level)
    app_level_command "$@"
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
    apply_space_layout "$target"
    ;;
  space-layout)
    layout=${1:-}
    if [[ -z "$layout" ]]; then
      echo "Usage: $0 space-layout <bsp|stack|float>" >&2
      exit 1
    fi
    apply_space_layout "$layout"
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
  window-toggle-pip)
    window_toggle_property pip
    ;;
  window-close)
    run_window_command --close
    refresh_front_app_state
    ;;
  window-focus-next-wrap)
    window_focus_next_wrap
    ;;
  window-insert-east)
    window_insert_direction east
    ;;
  window-insert-south)
    window_insert_direction south
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
  window-minimize)
    run_window_command --minimize
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
  space-focus)
    space_focus_index "${1:-}"
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
  window-swap-recent)
    window_swap_direction recent
    ;;
  window-zoom-master|zoom-master)
    window_zoom_master
    ;;
  window-stack-next|stack-next)
    window_stack_cycle next
    ;;
  window-stack-prev|stack-prev)
    window_stack_cycle prev
    ;;
  window-resize)
    window_resize_direction "${1:-east}" "${2:-40}"
    ;;
  space-toggle-monocle|toggle-monocle)
    layout=$(current_space_layout)
    case "$layout" in
      stack) apply_space_layout bsp ;;
      *) apply_space_layout stack ;;
    esac
    ;;
  feature-toggle)
    feature_toggle_command "$@"
    ;;
  workflow-policy)
    workflow_policy_command "$@"
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
  status [--json]
  spaces [--json]
  windows [--json]
  start
  restart
  wm-mode <required|optional|disabled|auto>
  app-default-current <float|tile|unset>
  app-default <list|set <App Name> <float|tile>|unset <App Name>>
  app-level-current <normal|raised|top|unset>
  app-level <list|set <App Name> <normal|raised|top>|unset <App Name>>
  space-create [--display <index|active>] [--force]
  space-destroy [space] [--force]
  space-move-left [space]
  space-move-right [space]
  space-move-display-prev [space]
  space-move-display-next [space]
  space-prune [--dry-run]
  space-lock <space-or-uuid>
  space-unlock <space-or-uuid>
  space-policy [list [--json]|get <key>|set <key> <value>]
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
  window-toggle-pip
  window-close
  window-focus-next-wrap
  window-insert-east|window-insert-south
  window-toggle-topmost
  window-preset-utility|window-preset-focus|window-preset-presentation|window-preset-tile-here
  window-adopt-space-mode [space]
  window-center
  window-minimize
  window-display-next|window-display-prev
  window-space-next|window-space-prev
  window-space <index>
  window-space-float
  space-focus-prev-wrap|space-focus-next-wrap
  space-focus <positive-index>
  display-focus-prev-wrap|display-focus-next-wrap
  window-focus-west|window-focus-south|window-focus-north|window-focus-east
  window-swap-west|window-swap-south|window-swap-north|window-swap-east|window-swap-recent
  space-prev|space-next|space-recent|space-first|space-last
  window-space-prev-wrap|window-space-next-wrap
  space-focus-app <AppName>
  shortcuts [--json]
  rules-audit [--json]
  doctor [--fix] [--probe-focus]
USAGE
    exit 1
    ;;
 esac
