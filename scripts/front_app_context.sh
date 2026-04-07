#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"
[ -z "$_d" ] && _d="."
ROOT_DIR="$(cd "$_d/.." && pwd)"
[ -r "$ROOT_DIR/plugins/lib/common.sh" ] && . "$ROOT_DIR/plugins/lib/common.sh"

YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-$SCRIPTS_DIR/runtime_context.sh}"
MODE="full"
APP_NAME="${INFO:-}"

emit() {
  printf '%s\t%s\n' "$1" "$2"
}

usage() {
  echo "Usage: $0 [--mode full|focused-space] [--app APP_NAME]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --app)
      APP_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

query_runtime_context() {
  local command_name="front-app"
  local output runtime_app_name

  [ -x "$RUNTIME_CONTEXT_SCRIPT" ] || return 1
  if [ "$MODE" = "focused-space" ]; then
    command_name="focused-space"
  fi

  if ! output="$("$RUNTIME_CONTEXT_SCRIPT" "$command_name" 2>/dev/null)"; then
    output=""
  fi
  [ -n "$output" ] || return 1

  if [ -n "$APP_NAME" ]; then
    runtime_app_name="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "app_name" { print $2; exit }')"
    if [ -n "$runtime_app_name" ] && [ "$runtime_app_name" != "$APP_NAME" ]; then
      return 1
    fi
  fi

  printf '%s\n' "$output"
  return 0
}

query_json() {
  [ -n "$YABAI_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m "$@" 2>/dev/null || true
}

query_spaces_json() {
  query_json query --spaces
}

query_current_space_json() {
  local spaces_json
  spaces_json="$(query_spaces_json)"
  [ -n "$spaces_json" ] || return 0
  printf '%s\n' "$spaces_json" | "$JQ_BIN" -c '
    (map(select(."has-focus" == true))[0])
    // (map(select(."is-visible" == true))[0])
    // empty
  ' 2>/dev/null || true
}

query_space_json_by_index() {
  local space_index="${1:-}"
  [ -n "$space_index" ] || return 0
  query_json query --spaces --space "$space_index"
}

query_focused_window_json() {
  query_json query --windows --window
}

query_all_windows_json() {
  query_json query --windows
}

resolve_front_app_name() {
  local app_name="${APP_NAME:-}"
  local focused_window_json
  if [ -n "$app_name" ]; then
    printf '%s' "$app_name"
    return 0
  fi

  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    focused_window_json="$(query_focused_window_json)"
    if [ -n "$focused_window_json" ]; then
      app_name="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '.app // empty' 2>/dev/null || true)"
      if [ -n "$app_name" ]; then
        printf '%s' "$app_name"
        return 0
      fi
    fi
  fi

  [ -n "$OSASCRIPT_BIN" ] || return 0
  "$OSASCRIPT_BIN" -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true
}

select_matching_window_json() {
  local app_name="${1:-}"
  local current_space="${2:-0}"
  local current_display="${3:-0}"
  local focused_window_json all_windows_json

  [ -n "$app_name" ] || return 0
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 0

  focused_window_json="$(query_focused_window_json)"
  if [ -n "$focused_window_json" ]; then
    if printf '%s\n' "$focused_window_json" | "$JQ_BIN" -e --arg app "$app_name" \
      '(.app // "") == $app and (."is-minimized" // false) == false' >/dev/null 2>&1; then
      printf '%s' "$focused_window_json"
      return 0
    fi
  fi

  all_windows_json="$(query_all_windows_json)"
  [ -n "$all_windows_json" ] || return 0
  printf '%s\n' "$all_windows_json" | "$JQ_BIN" -c \
    --arg app "$app_name" \
    --argjson space "$current_space" \
    --argjson display "$current_display" '
      map(select((.app // "") == $app and (."is-minimized" // false) == false))
      | sort_by(
          (if ."has-focus" == true then 0 else 1 end),
          (if (.space // 0) == $space then 0 else 1 end),
          (if (.display // 0) == $display then 0 else 1 end),
          (.id // 0)
        )
      | .[0] // empty
    ' 2>/dev/null || true
}

space_type_for_index() {
  local space_index="${1:-}"
  local current_space_json="${2:-}"
  local current_space_index current_space_type

  [ -n "$space_index" ] || return 0

  if [ -n "$current_space_json" ]; then
    current_space_index="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.index // empty' 2>/dev/null || true)"
    if [ -n "$current_space_index" ] && [ "$current_space_index" = "$space_index" ]; then
      current_space_type="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.type // empty' 2>/dev/null || true)"
      if [ -n "$current_space_type" ] && [ "$current_space_type" != "null" ]; then
        printf '%s' "$current_space_type"
        return 0
      fi
    fi
  fi

  query_space_json_by_index "$space_index" | "$JQ_BIN" -r '.type // empty' 2>/dev/null || true
}

append_space_context_label() {
  local label="${1:-}"
  local floating="${2:-false}"
  local space_type="${3:-}"

  case "$space_type" in
    float)
      printf '%s' "$label · Float Space"
      ;;
    bsp|stack)
      if [ "$floating" = "true" ]; then
        printf '%s' "$label · Managed Space"
      else
        printf '%s' "$label"
      fi
      ;;
    *)
      printf '%s' "$label"
      ;;
  esac
}

build_state_label() {
  local window_json="${1:-}"
  local space_type="${2:-}"
  local floating sticky fullscreen layer label

  floating="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."is-floating" // false' 2>/dev/null || echo false)"
  sticky="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."is-sticky" // false' 2>/dev/null || echo false)"
  fullscreen="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."has-fullscreen-zoom" // ."is-native-fullscreen" // false' 2>/dev/null || echo false)"
  layer="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.layer // "normal"' 2>/dev/null || echo normal)"

  if [ "$fullscreen" = "true" ]; then
    emit state_icon "󰊓"
    label="Fullscreen"
  elif [ "$floating" = "true" ]; then
    emit state_icon "󰒄"
    label="Floating"
  else
    emit state_icon "󰆾"
    label="Tiled"
  fi

  if [ "$sticky" = "true" ]; then
    label="$label · Sticky"
  fi

  case "$layer" in
    above) label="$label · Above" ;;
    below) label="$label · Below" ;;
  esac

  label="$(append_space_context_label "$label" "$floating" "$space_type")"
  emit state_label "$label"
}

main() {
  local app_name current_space_json current_space_index current_display_index current_space_visible
  local window_json window_space window_display window_focused window_space_type
  local runtime_output

  runtime_output="$(query_runtime_context || true)"
  if [ -n "$runtime_output" ]; then
    printf '%s\n' "$runtime_output"
    exit 0
  fi

  app_name="$(resolve_front_app_name)"
  [ -n "$app_name" ] || exit 0

  current_space_json=""
  current_space_index=""
  current_display_index=""
  current_space_visible="false"
  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    current_space_json="$(query_current_space_json)"
    if [ -n "$current_space_json" ]; then
      current_space_index="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.index // empty' 2>/dev/null || true)"
      current_display_index="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.display // empty' 2>/dev/null || true)"
      current_space_visible="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '."is-visible" // false' 2>/dev/null || echo false)"
    fi
  fi

  emit app_name "$app_name"

  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    window_json="$(select_matching_window_json "$app_name" "${current_space_index:-0}" "${current_display_index:-0}")"
  else
    window_json=""
  fi

  if [ -n "$window_json" ]; then
    window_space="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.space // empty' 2>/dev/null || true)"
    window_display="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.display // empty' 2>/dev/null || true)"
    window_focused="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."has-focus" // false' 2>/dev/null || echo false)"
    window_space_type="$(space_type_for_index "${window_space:-${current_space_index:-}}" "$current_space_json")"

    if [ -z "$current_space_index" ] && [ -n "$window_space" ]; then
      current_space_index="$window_space"
    fi
    if [ -z "$current_display_index" ] && [ -n "$window_display" ]; then
      current_display_index="$window_display"
    fi
    if [ "${current_space_visible:-false}" != "true" ] && [ "$window_focused" = "true" ]; then
      current_space_visible="true"
    fi
  fi

  emit space_index "${current_space_index:-}"
  emit display_index "${current_display_index:-}"
  emit space_visible "${current_space_visible:-false}"

  if [ "$MODE" = "focused-space" ]; then
    exit 0
  fi

  if [ -n "$window_json" ]; then
    emit window_available "true"
    build_state_label "$window_json" "$window_space_type"
    emit location_label "Space ${window_space:-${current_space_index:-?}} · Display ${window_display:-${current_display_index:-?}}"
    exit 0
  fi

  emit window_available "false"
  emit state_icon "󰋽"
  emit state_label "No managed window"
  emit location_label "Space ${current_space_index:-?} · Display ${current_display_index:-?}"
}

main "$@"
