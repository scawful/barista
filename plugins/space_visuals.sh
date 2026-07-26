#!/bin/bash

set -euo pipefail

PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
# common.sh resolves the real binary before defining the sketchybar() wrapper.
# Preserve that value instead of resolving the wrapper function name.
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
PERF_STATS_BIN="$CONFIG_DIR/bin/barista-stats.sh"
ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
SPACE_VISUAL_HELPER_BIN="${BARISTA_SPACE_VISUAL_HELPER_BIN:-$CONFIG_DIR/bin/space_visual_helper}"
PERF_CLOCK_BIN="${BARISTA_PERF_CLOCK_BIN:-$CONFIG_DIR/bin/perf_clock}"
MV_BIN="${BARISTA_MV_BIN:-/bin/mv}"
FILE_LOCK_BIN="${BARISTA_FILE_LOCK_BIN:-$CONFIG_DIR/bin/file_lock}"
FILE_LOCK_SOURCE="${BARISTA_FILE_LOCK_SOURCE:-$CONFIG_DIR/helpers/file_lock.c}"
FILE_LOCK_CC="${BARISTA_FILE_LOCK_CC:-}"
FLOCK_BIN="${BARISTA_FLOCK_BIN:-/usr/bin/flock}"
PYTHON_BIN="${BARISTA_PYTHON_BIN:-}"
PORTABLE_LOCK_ONLY=0
if [ "${BARISTA_LUA_ONLY:-0}" = "1" ] || [ "${BARISTA_NO_CMAKE:-0}" = "1" ]; then
  PORTABLE_LOCK_ONLY=1
fi
if [ "$PORTABLE_LOCK_ONLY" -eq 1 ] && [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="$(command -v python3 2>/dev/null || true)"
fi
BARISTA_ALL_SPACES_DATA="${BARISTA_ALL_SPACES_DATA:-}"
STATE_FILE="${STATE_FILE:-$CONFIG_DIR/state.json}"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
APP_GLYPH_CACHE_DIR="$CONFIG_DIR/cache/app_glyphs"
APP_GLYPH_CACHE_VERSION="2"
APP_GLYPH_CACHE_VERSION_FILE="$APP_GLYPH_CACHE_DIR/.version"
SPACE_VISUALS_STATE_DIR="$CONFIG_DIR/cache/space_visuals"
SPACE_VISUALS_LOCK_FILE="$SPACE_VISUALS_STATE_DIR/visual.lock"
SPACE_VISUALS_LOCK_HELD=0
SPACE_VISUALS_LOCK_BACKEND=""
FRONT_APP_VISUAL_RETRY_LOCK_FILE="$SPACE_VISUALS_STATE_DIR/front_app_retry.lock"
FRONT_APP_VISUAL_RETRY_LOCK_HELD=0
FRONT_APP_VISUAL_RETRY_LOCK_BACKEND=""
FRONT_APP_VISUAL_WAIT_ATTEMPTS="${BARISTA_SPACE_FRONT_APP_VISUAL_WAIT_ATTEMPTS:-240}"
FRONT_APP_VISUAL_WAIT_DELAY="${BARISTA_SPACE_FRONT_APP_VISUAL_WAIT_DELAY:-0.025}"
FRONT_APP_VISUAL_WAITED=0
SPACE_REFRESH_LOCK_DIR="${BARISTA_SPACE_REFRESH_LOCK_DIR:-$CONFIG_DIR/.refresh_spaces.lock}"
STARTUP_TOPOLOGY_WAIT_ATTEMPTS="${BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_ATTEMPTS:-20}"
STARTUP_TOPOLOGY_WAIT_DELAY="${BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_DELAY:-0.10}"
STARTUP_TOPOLOGY_WAIT_TIMED_OUT=0
FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS="${BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS:-40}"
FRONT_APP_TOPOLOGY_WAIT_DELAY="${BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_DELAY:-0.05}"
FRONT_APP_TOPOLOGY_WAITED=0
FRONT_APP_COOLDOWN_MS="${BARISTA_SPACE_FRONT_APP_COOLDOWN_MS:-1200}"
FRONT_APP_DEBOUNCE_MS="${BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS:-250}"
STARTUP_SYNC_COOLDOWN_MS="${BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS:-4000}"
LAST_AUTHORITATIVE_REFRESH_FILE="$SPACE_VISUALS_STATE_DIR/last_authoritative_refresh_ms"
LAST_FRONT_APP_REFRESH_FILE="$SPACE_VISUALS_STATE_DIR/last_front_app_refresh_ms"
SPACE_ITEM_LOOKUP_FILE="$SPACE_VISUALS_STATE_DIR/space_items"
STATE_SPACE_MAPS_LOADED=0
SPACE_ITEM_LOOKUP_LOADED=0
CACHED_SPACE_ICONS_LOADED=0
PHASE_METRICS_ENABLED="${BARISTA_SPACE_VISUAL_PHASE_METRICS:-0}"
SPACE_VISUAL_PATH="full"
PHASE_SPACES_MS=0
PHASE_LOOKUP_MS=0
PHASE_STATE_MS=0
PHASE_LOOP_MS=0
PHASE_APP_MS=0
PHASE_GLYPH_MS=0
PHASE_STYLE_MS=0
PHASE_APPLY_MS=0
STYLE_WRITES=0
STYLE_SKIPS=0
STYLE_ARGS_INITIALIZED=0
STYLE_STATE_DIR_READY=0
STYLE_STATE_ROOT_CACHE="$SPACE_VISUALS_STATE_DIR/style_state"
STYLE_FOCUSED_PROPS=""
STYLE_VISIBLE_PROPS=""
STYLE_IDLE_PROPS=""

declare -a STATE_DEFAULT_ICONS
declare -a STATE_SPACE_MODES
declare -a CACHED_SPACE_ICONS
declare -a SPACE_APP_BY_INDEX
declare -a SPACE_APP_LOADED
declare -a SPACE_ITEM_PRESENT
declare -a STYLE_FOCUSED_ARGS
declare -a STYLE_VISIBLE_ARGS
declare -a STYLE_IDLE_ARGS

EMPTY_ICON="○"
ACTIVE_EMPTY_ICON="•"
LAST_SELECTED_SPACE_FILE="$SPACE_VISUALS_STATE_DIR/last_selected_space"
LAST_SELECTED_CONTEXT_FILE="$SPACE_VISUALS_STATE_DIR/last_selected_context"

[ -r "${_d}/lib/space_style.sh" ] && . "${_d}/lib/space_style.sh"

init_cached_style_args() {
  [ "$STYLE_ARGS_INITIALIZED" -eq 0 ] || return 0
  STYLE_ARGS_INITIALIZED=1

  STYLE_FOCUSED_ARGS=(
    "label.drawing=off"
    "background.drawing=on"
    "background.color=$SPACE_FOCUSED_BG"
    "background.border_width=$SPACE_FOCUSED_BORDER_WIDTH"
    "background.border_color=$SPACE_FOCUSED_BORDER_COLOR"
    "icon.color=$SPACE_FOCUSED_ICON_COLOR"
  )
  STYLE_VISIBLE_ARGS=(
    "label.drawing=off"
    "background.drawing=on"
    "background.color=$SPACE_VISIBLE_BG"
    "background.border_width=$SPACE_VISIBLE_BORDER_WIDTH"
    "background.border_color=$SPACE_VISIBLE_BORDER_COLOR"
    "icon.color=$SPACE_VISIBLE_ICON_COLOR"
  )
  STYLE_IDLE_ARGS=(
    "label.drawing=off"
    "background.drawing=on"
    "background.color=$SPACE_IDLE_BG"
    "background.border_width=$SPACE_IDLE_BORDER_WIDTH"
    "background.border_color=$SPACE_IDLE_BORDER_COLOR"
    "icon.color=$SPACE_IDLE_ICON_COLOR"
  )

  printf -v STYLE_FOCUSED_PROPS '%s\n%s\n%s\n%s\n%s\n%s' "${STYLE_FOCUSED_ARGS[@]}"
  printf -v STYLE_VISIBLE_PROPS '%s\n%s\n%s\n%s\n%s\n%s' "${STYLE_VISIBLE_ARGS[@]}"
  printf -v STYLE_IDLE_PROPS '%s\n%s\n%s\n%s\n%s\n%s' "${STYLE_IDLE_ARGS[@]}"
}

cached_space_style_props_into() {
  local output_name="${1:-}"
  local state="${2:-idle}"
  local output_value=""
  [ -n "$output_name" ] || return 1
  init_cached_style_args
  case "$state" in
    focused) output_value="$STYLE_FOCUSED_PROPS" ;;
    visible) output_value="$STYLE_VISIBLE_PROPS" ;;
    idle|*) output_value="$STYLE_IDLE_PROPS" ;;
  esac
  printf -v "$output_name" '%s' "$output_value"
}

append_cached_style_args_to_fast() {
  init_cached_style_args
  case "${1:-idle}" in
    focused) FAST_ARGS+=("${STYLE_FOCUSED_ARGS[@]}") ;;
    visible) FAST_ARGS+=("${STYLE_VISIBLE_ARGS[@]}") ;;
    idle|*) FAST_ARGS+=("${STYLE_IDLE_ARGS[@]}") ;;
  esac
}

ensure_style_state_dir() {
  [ "$STYLE_STATE_DIR_READY" -eq 0 ] || return 0
  STYLE_STATE_DIR_READY=1
  mkdir -p "$STYLE_STATE_ROOT_CACHE" 2>/dev/null || true
}

invalidate_style_state_cache() {
  [ -d "$STYLE_STATE_ROOT_CACHE" ] || return 0
  rm -f "$STYLE_STATE_ROOT_CACHE"/space.*.state >/dev/null 2>&1 || true
}

style_state_file_for_item_into() {
  local output_name="${1:-}"
  local item="${2:-}"
  local output_value=""
  [ -n "$output_name" ] || return 1
  [ -n "$item" ] || return 1
  case "$item" in
    *[!A-Za-z0-9._-]*)
      output_value="$(space_style_state_file "$item")"
      ;;
    *)
      output_value="$STYLE_STATE_ROOT_CACHE/$item.state"
      ;;
  esac
  printf -v "$output_name" '%s' "$output_value"
}

style_state_matches_file() {
  local state_file="${1:-}"
  local state="${2:-idle}"
  local style_props="${3:-}"
  local first=1 first_line="" line saved_props=""
  [ -f "$state_file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first_line="$line"
      first=0
      continue
    fi
    if [ -n "$saved_props" ]; then
      saved_props="${saved_props}
${line}"
    else
      saved_props="$line"
    fi
  done < "$state_file"

  [ "$first" -eq 0 ] || return 1
  [ "$first_line" = "state=$state" ] || return 1
  [ "$saved_props" = "$style_props" ]
}

now_ms() {
  local native_ms=""
  if [ "${BARISTA_LUA_ONLY:-0}" != "1" ] && [ -x "$PERF_CLOCK_BIN" ]; then
    if native_ms="$("$PERF_CLOCK_BIN" 2>/dev/null)"; then
      case "$native_ms" in
        ''|*[!0-9]*) ;;
        *)
          printf '%s\n' "$native_ms"
          return
          ;;
      esac
    fi
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf("%d\n", time() * 1000)'
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
    return
  fi
  date +%s | awk '{print $1 "000"}'
}

phase_begin() {
  local output_name="${1:-}"
  local start_value=0
  [ -n "$output_name" ] || return 1
  if [ "$PHASE_METRICS_ENABLED" = "1" ]; then
    start_value="$(now_ms)"
  fi
  printf -v "$output_name" '%s' "$start_value"
}

phase_add() {
  [ "$PHASE_METRICS_ENABLED" = "1" ] || return 0
  local var_name="${1:-}"
  local start_ms="${2:-0}"
  local end_ms delta current
  [ -n "$var_name" ] || return 0
  end_ms="$(now_ms)"
  delta=$((end_ms - start_ms))
  current="${!var_name:-0}"
  printf -v "$var_name" '%s' "$((current + delta))"
}

read_file_value() {
  local path="${1:-}"
  local value=""
  [ -n "$path" ] || return 0
  [ -f "$path" ] || return 0
  IFS= read -r value < "$path" || true
  printf '%s' "$value"
}

load_cached_space_icons() {
  [ "$CACHED_SPACE_ICONS_LOADED" -eq 0 ] || return 0
  CACHED_SPACE_ICONS_LOADED=1
  [ -d "$ICON_CACHE_DIR" ] || return 0

  local cache_file cache_name cache_value
  shopt -s nullglob
  for cache_file in "$ICON_CACHE_DIR"/*; do
    [ -f "$cache_file" ] || continue
    cache_name="${cache_file##*/}"
    case "$cache_name" in
      ''|*[!0-9]*)
        continue
        ;;
    esac
    cache_value="$(read_file_value "$cache_file")"
    [ -n "$cache_value" ] || continue
    CACHED_SPACE_ICONS[$cache_name]="$cache_value"
  done
  shopt -u nullglob
}

record_perf() {
  local start_ms="${1:-}"
  local spaces_count="${2:-0}"
  local visible_count="${3:-0}"
  local path="${4:-$SPACE_VISUAL_PATH}"
  [ -n "$start_ms" ] || return 0
  [ -x "$PERF_STATS_BIN" ] || return 0
  local end_ms duration meta_json=""
  end_ms="$(now_ms)"
  duration=$((end_ms - start_ms))
  if [ "$PHASE_METRICS_ENABLED" = "1" ] && [ -n "$JQ_BIN" ]; then
    meta_json="$("$JQ_BIN" -cn \
      --arg path "$path" \
      --argjson spaces "$spaces_count" \
      --argjson visible "$visible_count" \
      --argjson spaces_ms "$PHASE_SPACES_MS" \
      --argjson lookup_ms "$PHASE_LOOKUP_MS" \
      --argjson state_ms "$PHASE_STATE_MS" \
      --argjson loop_ms "$PHASE_LOOP_MS" \
      --argjson app_ms "$PHASE_APP_MS" \
      --argjson glyph_ms "$PHASE_GLYPH_MS" \
      --argjson style_ms "$PHASE_STYLE_MS" \
      --argjson apply_ms "$PHASE_APPLY_MS" \
      --argjson style_writes "$STYLE_WRITES" \
      --argjson style_skips "$STYLE_SKIPS" \
      '{
        path: $path,
        spaces: $spaces,
        visible: $visible,
        spaces_ms: $spaces_ms,
        lookup_ms: $lookup_ms,
        state_ms: $state_ms,
        loop_ms: $loop_ms,
        app_ms: $app_ms,
        glyph_ms: $glyph_ms,
        style_ms: $style_ms,
        apply_ms: $apply_ms,
        style_writes: $style_writes,
        style_skips: $style_skips
      }' 2>/dev/null || true)"
  fi
  if [ -n "$meta_json" ]; then
    BARISTA_EVENT_META_JSON="$meta_json" "$PERF_STATS_BIN" event space_visual_refresh "$duration" \
      "sender=${SENDER:-manual} spaces=$spaces_count visible=$visible_count path=$path" >/dev/null 2>&1 || true
  else
    "$PERF_STATS_BIN" event space_visual_refresh "$duration" \
      "sender=${SENDER:-manual} spaces=$spaces_count visible=$visible_count path=$path" >/dev/null 2>&1 || true
  fi
}

read_cached_icon() {
  local space_index="${1:-}"
  [ -n "$space_index" ] || return 0
  load_cached_space_icons
  printf '%s' "${CACHED_SPACE_ICONS[$space_index]-}"
}

write_cached_icon() {
  local space_index="${1:-}"
  local icon_value="${2:-}"
  [ -n "$space_index" ] || return 0
  [ -n "$icon_value" ] || return 0
  mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || true
  printf '%s' "$icon_value" > "$ICON_CACHE_DIR/$space_index" 2>/dev/null || true
}

app_cache_key() {
  local app_name="${1:-}"
  [ -n "$app_name" ] || return 0
  printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]._' '_'
}

read_cached_app_glyph() {
  local app_name="${1:-}"
  local cache_key
  [ -n "$app_name" ] || return 0
  cache_key="$(app_cache_key "$app_name")"
  [ -n "$cache_key" ] || return 0
  read_file_value "$APP_GLYPH_CACHE_DIR/$cache_key"
}

write_cached_app_glyph() {
  local app_name="${1:-}"
  local glyph="${2:-}"
  local cache_key
  [ -n "$app_name" ] || return 0
  [ -n "$glyph" ] || return 0
  cache_key="$(app_cache_key "$app_name")"
  [ -n "$cache_key" ] || return 0
  mkdir -p "$APP_GLYPH_CACHE_DIR" 2>/dev/null || true
  printf '%s' "$glyph" > "$APP_GLYPH_CACHE_DIR/$cache_key" 2>/dev/null || true
}

read_ms_file() {
  local path="${1:-}"
  read_file_value "$path"
}

write_ms_file() {
  local path="${1:-}"
  local value="${2:-}"
  [ -n "$path" ] || return 0
  [ -n "$value" ] || return 0
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  printf '%s' "$value" > "$path" 2>/dev/null || true
}

read_last_selected_context() {
  local space_output_name="${1:-}"
  local display_output_name="${2:-}"
  local context_line=""
  local trailing_line=""
  local payload="" selected_space="" selected_display=""
  [ -n "$space_output_name" ] || return 1
  [ -n "$display_output_name" ] || return 1
  [ -f "$LAST_SELECTED_CONTEXT_FILE" ] || return 1
  {
    IFS= read -r context_line || return 1
    if IFS= read -r trailing_line || [ -n "$trailing_line" ]; then
      return 1
    fi
  } < "$LAST_SELECTED_CONTEXT_FILE"
  case "$context_line" in
    "v1"$'\t'*) payload="${context_line#"v1"$'\t'}" ;;
    *) return 1 ;;
  esac
  case "$payload" in
    *$'\t'*)
      selected_space="${payload%%$'\t'*}"
      selected_display="${payload#*$'\t'}"
      ;;
    *)
      return 1
      ;;
  esac
  case "$selected_space" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$selected_display" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf -v "$space_output_name" '%s' "$selected_space"
  printf -v "$display_output_name" '%s' "$selected_display"
}

write_last_selected_context() {
  local selected_space="${1:-}"
  local selected_display="${2:-}"
  local temp_file="$LAST_SELECTED_CONTEXT_FILE.tmp.$$"
  case "$selected_space" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$selected_display" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ ! -d "$LAST_SELECTED_CONTEXT_FILE" ] || return 1
  if [ ! -d "$SPACE_VISUALS_STATE_DIR" ]; then
    mkdir -p "$SPACE_VISUALS_STATE_DIR" 2>/dev/null || return 1
  fi
  if printf 'v1\t%s\t%s\n' "$selected_space" "$selected_display" > "$temp_file" 2>/dev/null &&
      "$MV_BIN" -f "$temp_file" "$LAST_SELECTED_CONTEXT_FILE" 2>/dev/null; then
    if [ -e "$LAST_SELECTED_SPACE_FILE" ]; then
      rm -f "$LAST_SELECTED_SPACE_FILE" >/dev/null 2>&1 || true
    fi
    return 0
  fi
  rm -f "$temp_file" "$LAST_SELECTED_CONTEXT_FILE" >/dev/null 2>&1 || true
  return 1
}

invalidate_selected_context() {
  rm -f "$LAST_SELECTED_CONTEXT_FILE" "$LAST_SELECTED_SPACE_FILE" >/dev/null 2>&1 || true
}

invalidate_visual_recovery_state() {
  invalidate_style_state_cache
  invalidate_selected_context
  rm -f "$LAST_AUTHORITATIVE_REFRESH_FILE" >/dev/null 2>&1 || true
}

append_style_args() {
  local item="${1:-}"
  local state="${2:-idle}"
  local style_props="" style_start_ms
  [ -n "$item" ] || return 0
  phase_begin style_start_ms
  cached_space_style_props_into style_props "$state"
  remember_style_state "$item" "$state" "$style_props"
  append_cached_style_args_to_fast "$state"
  phase_add PHASE_STYLE_MS "$style_start_ms"
}

remember_style_state() {
  local item="${1:-}"
  local state="${2:-idle}"
  local style_props="${3:-}"
  local state_file
  [ -n "$item" ] || return 0
  if [ -z "$style_props" ]; then
    cached_space_style_props_into style_props "$state"
  fi

  style_state_file_for_item_into state_file "$item" 2>/dev/null || true
  [ -n "$state_file" ] || return 0
  if style_state_matches_file "$state_file" "$state" "$style_props"; then
    STYLE_SKIPS=$((STYLE_SKIPS + 1))
    return 0
  fi

  ensure_style_state_dir
  {
    printf 'state=%s\n' "$state"
    printf '%s\n' "$style_props"
  } > "$state_file" 2>/dev/null || true
  STYLE_WRITES=$((STYLE_WRITES + 1))
}

cleanup_visual_locks() {
  if [ "$SPACE_VISUALS_LOCK_HELD" -eq 1 ]; then
    case "$SPACE_VISUALS_LOCK_BACKEND" in
      native|flock|python) exec 9>&- ;;
    esac
    SPACE_VISUALS_LOCK_HELD=0
    SPACE_VISUALS_LOCK_BACKEND=""
  fi
  if [ "$FRONT_APP_VISUAL_RETRY_LOCK_HELD" -eq 1 ]; then
    case "$FRONT_APP_VISUAL_RETRY_LOCK_BACKEND" in
      native|flock|python) exec 8>&- ;;
    esac
    FRONT_APP_VISUAL_RETRY_LOCK_HELD=0
    FRONT_APP_VISUAL_RETRY_LOCK_BACKEND=""
  fi
}

acquire_lock_fd() {
  local fd="${1:-}"
  [ -n "$fd" ] || return 1
  if [ "$PORTABLE_LOCK_ONLY" -eq 1 ]; then
    [ -x "$PYTHON_BIN" ] || return 1
    "$PYTHON_BIN" -c '
import fcntl
import sys

try:
    descriptor = int(sys.argv[1])
    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit(75)
except (OSError, ValueError):
    raise SystemExit(74)
' "$fd" >/dev/null 2>&1
    return $?
  fi
  if [ -x "$FILE_LOCK_BIN" ]; then
    "$FILE_LOCK_BIN" "$fd" >/dev/null 2>&1
    return $?
  fi
  [ -x "$FLOCK_BIN" ] || return 1
  "$FLOCK_BIN" -n "$fd" >/dev/null 2>&1
}

ensure_file_lock_helper() {
  local cc_bin="$FILE_LOCK_CC"
  local temp_bin="$FILE_LOCK_BIN.tmp.$$"
  [ "$PORTABLE_LOCK_ONLY" -eq 0 ] || return 1
  [ -x "$FILE_LOCK_BIN" ] && return 0
  [ "$(uname -s)" = "Darwin" ] || return 1
  [ -f "$FILE_LOCK_SOURCE" ] || return 1
  if [ -z "$cc_bin" ]; then
    cc_bin="$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)"
  fi
  [ -n "$cc_bin" ] || return 1
  mkdir -p "$(dirname "$FILE_LOCK_BIN")" 2>/dev/null || return 1
  if "$cc_bin" -std=c99 -O2 -mmacosx-version-min=13.0 \
      "$FILE_LOCK_SOURCE" -o "$temp_bin" >/dev/null 2>&1 &&
      chmod +x "$temp_bin" 2>/dev/null &&
      "$MV_BIN" -f "$temp_bin" "$FILE_LOCK_BIN" 2>/dev/null; then
    return 0
  fi
  rm -f "$temp_bin" >/dev/null 2>&1 || true
  return 1
}

acquire_visual_lock() {
  if { [ "$PORTABLE_LOCK_ONLY" -eq 1 ] && [ -x "$PYTHON_BIN" ]; } ||
      [ -x "$FILE_LOCK_BIN" ] || [ -x "$FLOCK_BIN" ]; then
    exec 9>"$SPACE_VISUALS_LOCK_FILE" || return 1
    if acquire_lock_fd 9; then
      SPACE_VISUALS_LOCK_HELD=1
      if [ "$PORTABLE_LOCK_ONLY" -eq 1 ]; then
        SPACE_VISUALS_LOCK_BACKEND="python"
      elif [ -x "$FILE_LOCK_BIN" ]; then
        SPACE_VISUALS_LOCK_BACKEND="native"
      else
        SPACE_VISUALS_LOCK_BACKEND="flock"
      fi
      trap cleanup_visual_locks EXIT
      return 0
    fi
    exec 9>&-
    return 1
  fi
  return 1
}

acquire_front_app_visual_retry_lock() {
  if { [ "$PORTABLE_LOCK_ONLY" -eq 1 ] && [ -x "$PYTHON_BIN" ]; } ||
      [ -x "$FILE_LOCK_BIN" ] || [ -x "$FLOCK_BIN" ]; then
    exec 8>"$FRONT_APP_VISUAL_RETRY_LOCK_FILE" || return 1
    if acquire_lock_fd 8; then
      FRONT_APP_VISUAL_RETRY_LOCK_HELD=1
      if [ "$PORTABLE_LOCK_ONLY" -eq 1 ]; then
        FRONT_APP_VISUAL_RETRY_LOCK_BACKEND="python"
      elif [ -x "$FILE_LOCK_BIN" ]; then
        FRONT_APP_VISUAL_RETRY_LOCK_BACKEND="native"
      else
        FRONT_APP_VISUAL_RETRY_LOCK_BACKEND="flock"
      fi
      trap cleanup_visual_locks EXIT
      return 0
    fi
    exec 8>&-
    return 1
  fi
  return 1
}

release_front_app_visual_retry_lock() {
  [ "$FRONT_APP_VISUAL_RETRY_LOCK_HELD" -eq 1 ] || return 0
  case "$FRONT_APP_VISUAL_RETRY_LOCK_BACKEND" in
    native|flock|python) exec 8>&- ;;
  esac
  FRONT_APP_VISUAL_RETRY_LOCK_HELD=0
  FRONT_APP_VISUAL_RETRY_LOCK_BACKEND=""
}

wait_for_front_app_visual_lock() {
  local attempts
  [ "${SENDER:-}" = "front_app_switched" ] || return 1

  # Only one waiter represents all front-app events that arrive while another
  # visual pass owns the lock. It refreshes from live focus context after the
  # owner exits; later contenders can return because this waiter covers them.
  acquire_front_app_visual_retry_lock || return 1

  attempts="$FRONT_APP_VISUAL_WAIT_ATTEMPTS"
  case "$attempts" in
    ""|*[!0-9]*) attempts=240 ;;
  esac
  while [ "$attempts" -gt 0 ]; do
    if acquire_visual_lock; then
      FRONT_APP_VISUAL_WAITED=1
      # Open the single retry slot before querying focus. An event that arrives
      # after this waiter snapshots context can queue behind the main lock and
      # become the next fresh-context pass instead of being dropped.
      release_front_app_visual_retry_lock
      return 0
    fi
    sleep "$FRONT_APP_VISUAL_WAIT_DELAY" 2>/dev/null || break
    attempts=$((attempts - 1))
  done
  return 1
}

should_skip_front_app_refresh() {
  local sender="${SENDER:-}"
  local last_authoritative last_front
  [ "$sender" = "front_app_switched" ] || return 1

  if [ "$FRONT_APP_TOPOLOGY_WAITED" -eq 0 ] &&
      [ "$FRONT_APP_VISUAL_WAITED" -eq 0 ]; then
    last_authoritative="$(read_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE")"
    if [ -n "$last_authoritative" ] && [ $((START_MS - last_authoritative)) -lt "$FRONT_APP_COOLDOWN_MS" ]; then
      return 0
    fi
  fi

  # Any visual-lock waiter can represent an event that arrived after the prior
  # owner sampled focus, so it must run once with fresh context even when that
  # owner just published a debounce marker.
  if [ "$FRONT_APP_VISUAL_WAITED" -eq 0 ]; then
    last_front="$(read_ms_file "$LAST_FRONT_APP_REFRESH_FILE")"
    if [ -n "$last_front" ] && [ $((START_MS - last_front)) -lt "$FRONT_APP_DEBOUNCE_MS" ]; then
      return 0
    fi
  fi

  return 1
}

should_skip_startup_sync() {
  local sender="${SENDER:-}"
  local last_authoritative
  [ "$sender" = "startup_sync" ] || return 1
  [ "$STARTUP_TOPOLOGY_WAIT_TIMED_OUT" -eq 0 ] || return 1

  last_authoritative="$(read_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE")"
  [ -n "$last_authoritative" ] || return 1
  [ $((START_MS - last_authoritative)) -lt "$STARTUP_SYNC_COOLDOWN_MS" ]
}

wait_for_front_app_topology_refresh() {
  local attempts
  [ "${SENDER:-}" = "front_app_switched" ] || return 0
  [ -d "$SPACE_REFRESH_LOCK_DIR" ] || return 0
  FRONT_APP_TOPOLOGY_WAITED=1
  attempts="$FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS"
  case "$attempts" in
    ""|*[!0-9]*) attempts=40 ;;
  esac

  # Wait outside the visual lock so topology can finish its authoritative pass.
  # The bound fails open for a stale lock rather than dropping app updates.
  while [ -d "$SPACE_REFRESH_LOCK_DIR" ] && [ "$attempts" -gt 0 ]; do
    sleep "$FRONT_APP_TOPOLOGY_WAIT_DELAY" 2>/dev/null || break
    attempts=$((attempts - 1))
  done
}

wait_for_topology_refresh() {
  local attempts
  [ "${SENDER:-}" = "startup_sync" ] || return 0
  # Wait before taking the visual lock so the authoritative topology path can
  # finish its own visual pass. The bound fails open for dead/stale owners.
  attempts="$STARTUP_TOPOLOGY_WAIT_ATTEMPTS"
  case "$attempts" in
    ""|*[!0-9]*) attempts=20 ;;
  esac

  while [ -d "$SPACE_REFRESH_LOCK_DIR" ] && [ "$attempts" -gt 0 ]; do
    sleep "$STARTUP_TOPOLOGY_WAIT_DELAY" 2>/dev/null || break
    attempts=$((attempts - 1))
  done
  if [ -d "$SPACE_REFRESH_LOCK_DIR" ]; then
    STARTUP_TOPOLOGY_WAIT_TIMED_OUT=1
  fi
}

begin_sender_refresh() {
  case "${SENDER:-}" in
    space_topology_refresh|space_active_refresh|space_visual_refresh|display_changed|display_added|display_removed|manual|startup_sync)
      rm -f "$LAST_AUTHORITATIVE_REFRESH_FILE" >/dev/null 2>&1 || true
      ;;
  esac
}

mark_sender_refresh() {
  case "${SENDER:-}" in
    front_app_switched)
      write_ms_file "$LAST_FRONT_APP_REFRESH_FILE" "$START_MS"
      if [ "$SPACE_VISUAL_PATH" = "full" ]; then
        write_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE" "$START_MS"
      fi
      ;;
    space_topology_refresh|space_active_refresh|space_visual_refresh|display_changed|display_added|display_removed|manual|startup_sync)
      write_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE" "$START_MS"
      ;;
  esac
}

ensure_app_glyph_cache_version() {
  local current_version=""
  mkdir -p "$APP_GLYPH_CACHE_DIR" 2>/dev/null || true
  mkdir -p "$SPACE_VISUALS_STATE_DIR" 2>/dev/null || true
  current_version="$(read_file_value "$APP_GLYPH_CACHE_VERSION_FILE")"
  if [ "$current_version" = "$APP_GLYPH_CACHE_VERSION" ]; then
    return 0
  fi

  find "$APP_GLYPH_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f ! -name '.version' -delete 2>/dev/null || true
  if [ -d "$ICON_CACHE_DIR" ]; then
    find "$ICON_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  fi
  printf '%s' "$APP_GLYPH_CACHE_VERSION" > "$APP_GLYPH_CACHE_VERSION_FILE" 2>/dev/null || true
}

resolve_app_glyph() {
  local app="${1:-}"
  local glyph
  [ -n "$app" ] || return 0
  glyph="$(read_cached_app_glyph "$app")"
  if [ -n "$glyph" ]; then
    printf '%s' "$glyph"
    return 0
  fi
  if [ -x "$ICON_SCRIPT" ]; then
    glyph="$("$ICON_SCRIPT" "$app" 2>/dev/null || true)"
    if [ -n "$glyph" ]; then
      write_cached_app_glyph "$app" "$glyph"
      printf '%s' "$glyph"
    fi
  fi
}

space_visual_helper_available() {
  [ -x "$SPACE_VISUAL_HELPER_BIN" ]
}

prefetch_app_glyphs_for_loaded_spaces() {
  [ -x "$ICON_SCRIPT" ] || return 1

  local space_index app glyph cache_key missing_apps="" unique_apps="" batch_output=""
  for space_index in "${!SPACE_APP_BY_INDEX[@]}"; do
    app="${SPACE_APP_BY_INDEX[$space_index]-}"
    [ -n "$app" ] || continue
    glyph="$(read_cached_app_glyph "$app")"
    [ -n "$glyph" ] && continue
    if [ -n "$missing_apps" ]; then
      missing_apps="${missing_apps}
${app}"
    else
      missing_apps="$app"
    fi
  done

  [ -n "$missing_apps" ] || return 0
  unique_apps="$(printf '%s\n' "$missing_apps" | sort -u 2>/dev/null || printf '%s\n' "$missing_apps")"
  [ -n "$unique_apps" ] || return 0

  batch_output="$(printf '%s\n' "$unique_apps" | "$ICON_SCRIPT" --batch 2>/dev/null || true)"
  [ -n "$batch_output" ] || return 1

  while IFS=$'\t' read -r app glyph; do
    [ -n "$app" ] || continue
    [ -n "$glyph" ] || continue
    cache_key="$(app_cache_key "$app")"
    [ -n "$cache_key" ] || continue
    write_cached_app_glyph "$app" "$glyph"
  done <<EOF
$batch_output
EOF
}

prefetch_visible_space_apps() {
  space_visual_helper_available || return 1
  [ -n "$ALL_SPACES_DATA" ] && [ -n "$JQ_BIN" ] || return 1

  local visible_indexes="" index helper_output="" app helper_status=0
  visible_indexes="$(printf '%s\n' "$ALL_SPACES_DATA" | "$JQ_BIN" -r '
    sort_by(.display, .index)[]
    | select(."is-visible" == true and .index != null)
    | .index
  ' 2>/dev/null || true)"
  [ -n "$visible_indexes" ] || return 0

  local -a helper_args=()
  while IFS= read -r index || [ -n "$index" ]; do
    [ -n "$index" ] || continue
    helper_args+=("$index")
  done <<EOF
$visible_indexes
EOF

  [ "${#helper_args[@]}" -gt 0 ] || return 0
  helper_output="$(BARISTA_YABAI_BIN="$YABAI_BIN" "$SPACE_VISUAL_HELPER_BIN" visible-apps "${helper_args[@]}" 2>/dev/null)" || helper_status=$?
  [ "$helper_status" -eq 0 ] || return 1

  for index in "${helper_args[@]}"; do
    SPACE_APP_LOADED[$index]=1
    SPACE_APP_BY_INDEX[$index]=""
  done

  while IFS=$'\t' read -r index app; do
    [ -n "$index" ] || continue
    SPACE_APP_LOADED[$index]=1
    SPACE_APP_BY_INDEX[$index]="$app"
  done <<EOF
$helper_output
EOF

  return 0
}

refresh_single_visible_space_from_focus_context() {
  local sender="${SENDER:-}"
  local app_name="" current_space_index="" current_display_index="" current_space_visible="false"
  local last_selected_space="" last_selected_display="" previous_state="idle"
  local item default_icon cached_icon icon_value
  local phase_start style_props focus_context_ms=0
  local -a apply_args=()
  local -a previous_args=()
  local -a focused_args=()

  case "$sender" in
    front_app_switched|space_active_refresh)
      ;;
    *)
      return 1
      ;;
  esac
  [ -x "$FRONT_APP_CONTEXT_SCRIPT" ] || return 1
  [ -n "$SKETCHYBAR_BIN" ] || return 1

  phase_begin phase_start
  while IFS=$'\t' read -r key value; do
    case "$key" in
      app_name) app_name="$value" ;;
      space_index) current_space_index="$value" ;;
      display_index) current_display_index="$value" ;;
      space_visible) current_space_visible="$value" ;;
    esac
  done < <(
    if [ "$sender" = "front_app_switched" ] &&
        [ "$FRONT_APP_TOPOLOGY_WAITED" -eq 0 ] &&
        [ "$FRONT_APP_VISUAL_WAITED" -eq 0 ] &&
        [ -n "${INFO:-}" ]; then
      "$FRONT_APP_CONTEXT_SCRIPT" --mode focused-space --app "${INFO:-}" 2>/dev/null || true
    else
      "$FRONT_APP_CONTEXT_SCRIPT" --mode focused-space 2>/dev/null || true
    fi
  )
  if [ "$PHASE_METRICS_ENABLED" = "1" ]; then
    focus_context_ms=$(( $(now_ms) - phase_start ))
  fi

  [ -n "$app_name" ] || return 1
  case "$current_space_index" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$current_display_index" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$current_space_visible" = "true" ] || return 1
  read_last_selected_context last_selected_space last_selected_display || return 1
  if [ "$last_selected_space" = "$current_space_index" ] &&
      [ "$last_selected_display" != "$current_display_index" ]; then
    return 1
  fi
  if [ "$last_selected_space" != "$current_space_index" ] &&
      [ "$last_selected_display" != "$current_display_index" ]; then
    previous_state="visible"
  fi

  SPACE_VISUAL_PATH="focus"
  PHASE_SPACES_MS=$((PHASE_SPACES_MS + focus_context_ms))

  item="space.$current_space_index"
  phase_begin phase_start
  load_state_space_maps
  phase_add PHASE_STATE_MS "$phase_start"
  [ -s "$SPACE_ITEM_LOOKUP_FILE" ] || return 1
  phase_begin phase_start
  load_space_item_lookup
  phase_add PHASE_LOOKUP_MS "$phase_start"
  [ "${SPACE_ITEM_PRESENT[$current_space_index]-0}" = "1" ] || return 1
  if [ "$last_selected_space" != "$current_space_index" ]; then
    [ "${SPACE_ITEM_PRESENT[$last_selected_space]-0}" = "1" ] || return 1
  fi

  default_icon="${STATE_DEFAULT_ICONS[$current_space_index]-}"
  cached_icon="$(read_cached_icon "$current_space_index")"
  if [ -n "$default_icon" ]; then
    icon_value="$default_icon"
  else
    phase_begin phase_start
    icon_value="$(resolve_app_glyph "$app_name")"
    phase_add PHASE_GLYPH_MS "$phase_start"
    if [ -n "$icon_value" ]; then
      write_cached_icon "$current_space_index" "$icon_value"
    elif [ -n "$cached_icon" ]; then
      icon_value="$cached_icon"
    else
      icon_value="$ACTIVE_EMPTY_ICON"
    fi
  fi

  if [ -n "$last_selected_space" ] && [ "$last_selected_space" != "$current_space_index" ] && [ "${SPACE_ITEM_PRESENT[$last_selected_space]-0}" = "1" ]; then
    phase_begin phase_start
    init_cached_style_args
    cached_space_style_props_into style_props "$previous_state"
    remember_style_state "space.$last_selected_space" "$previous_state" "$style_props"
    if [ "$previous_state" = "visible" ]; then
      previous_args=("${STYLE_VISIBLE_ARGS[@]}")
    else
      previous_args=("${STYLE_IDLE_ARGS[@]}")
    fi
    apply_args+=(--set "space.$last_selected_space" "${previous_args[@]}")
    phase_add PHASE_STYLE_MS "$phase_start"
  fi

  phase_begin phase_start
  init_cached_style_args
  cached_space_style_props_into style_props focused
  remember_style_state "$item" focused "$style_props"
  focused_args=("${STYLE_FOCUSED_ARGS[@]}")
  apply_args+=(--set "$item" icon="$icon_value" "${focused_args[@]}")
  phase_add PHASE_STYLE_MS "$phase_start"
  phase_begin phase_start
  if ! "$SKETCHYBAR_BIN" "${apply_args[@]}" >/dev/null 2>&1; then
    invalidate_visual_recovery_state
    return 1
  fi
  phase_add PHASE_APPLY_MS "$phase_start"
  if ! write_last_selected_context "$current_space_index" "$current_display_index"; then
    invalidate_visual_recovery_state
    return 1
  fi

  record_perf "$START_MS" "1" "1" "$SPACE_VISUAL_PATH"
  return 0
}

resolve_visible_space_app() {
  local space_index="${1:-}"
  local windows_json="" app_name=""

  [ -n "$space_index" ] || return 0
  if [ "${SPACE_APP_LOADED[$space_index]-0}" = "1" ]; then
    printf '%s' "${SPACE_APP_BY_INDEX[$space_index]-}"
    return 0
  fi

  SPACE_APP_LOADED[$space_index]=1
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 0

  windows_json="$(run_with_timeout 1 "$YABAI_BIN" -m query --windows --space "$space_index" 2>/dev/null || true)"
  [ -n "$windows_json" ] || return 0

  app_name="$(printf '%s\n' "$windows_json" | "$JQ_BIN" -r '
    map(select(."is-minimized" == false))
    | sort_by((if .["has-focus"] == true then 0 else 1 end), -(.id // 0))
    | .[0].app // empty
  ' 2>/dev/null || true)"
  SPACE_APP_BY_INDEX[$space_index]="$app_name"
  printf '%s' "$app_name"
}

if [ "${SENDER:-}" = "forced" ]; then
  exit 0
fi

wait_for_topology_refresh
wait_for_front_app_topology_refresh
START_MS="$(now_ms)"

load_state_space_maps() {
  [ "$STATE_SPACE_MAPS_LOADED" -eq 0 ] || return 0
  STATE_SPACE_MAPS_LOADED=1
  [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ] || return 0

  local idx icon mode
  while IFS=$'\x1f' read -r idx icon mode; do
    [ -n "$idx" ] || continue
    STATE_DEFAULT_ICONS[$idx]="$icon"
    STATE_SPACE_MODES[$idx]="$mode"
  done < <("$JQ_BIN" -r '
    (.space_icons // {}) as $icons
    | (.space_modes // {}) as $modes
    | [($icons | keys[]?), ($modes | keys[]?)] | flatten | unique[]? as $idx
    | [$idx, ($icons[$idx] // ""), ($modes[$idx] // "")] | join("\u001f")
  ' "$STATE_FILE" 2>/dev/null || true)
}

load_space_item_lookup() {
  [ "$SPACE_ITEM_LOOKUP_LOADED" -eq 0 ] || return 0
  SPACE_ITEM_LOOKUP_LOADED=1
  [ -n "$SKETCHYBAR_BIN" ] && [ -n "$JQ_BIN" ] || return 0

  local item_name space_index refresh_lookup=0 shared_spaces_data
  if [ ! -f "$SPACE_ITEM_LOOKUP_FILE" ]; then
    refresh_lookup=1
  else
    case "${SENDER:-}" in
      manual|startup_sync|space_topology_refresh|display_changed|display_added|display_removed)
        refresh_lookup=1
        ;;
    esac
  fi

  if [ "$refresh_lookup" -eq 1 ]; then
    mkdir -p "$SPACE_VISUALS_STATE_DIR" 2>/dev/null || true
    shared_spaces_data="${BARISTA_ALL_SPACES_DATA:-${ALL_SPACES_DATA:-}}"
    if [ -n "$shared_spaces_data" ]; then
      printf '%s\n' "$shared_spaces_data" | "$JQ_BIN" -r '.[] | select(.index != null) | "space.\(.index)"' \
        > "$SPACE_ITEM_LOOKUP_FILE" 2>/dev/null || true
    else
      "$SKETCHYBAR_BIN" --query bar 2>/dev/null | "$JQ_BIN" -r '.items[] | select(startswith("space."))' \
        > "$SPACE_ITEM_LOOKUP_FILE" 2>/dev/null || true
    fi
  fi

  [ -f "$SPACE_ITEM_LOOKUP_FILE" ] || return 0
  while IFS= read -r item_name; do
    case "$item_name" in
      space.[0-9]*)
        space_index="${item_name#space.}"
        SPACE_ITEM_PRESENT[$space_index]=1
        ;;
    esac
  done < "$SPACE_ITEM_LOOKUP_FILE"
}

ensure_app_glyph_cache_version
ensure_file_lock_helper || true

if ! acquire_visual_lock; then
  if ! wait_for_front_app_visual_lock; then
    exit 0
  fi
fi

if should_skip_front_app_refresh; then
  exit 0
fi

if should_skip_startup_sync; then
  exit 0
fi

begin_sender_refresh

if refresh_single_visible_space_from_focus_context; then
  mark_sender_refresh
  exit 0
fi
SPACE_VISUAL_PATH="full"
if [ "${SENDER:-}" = "front_app_switched" ]; then
  rm -f "$LAST_AUTHORITATIVE_REFRESH_FILE" >/dev/null 2>&1 || true
fi

[ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || exit 0

ALL_SPACES_DATA="$BARISTA_ALL_SPACES_DATA"
if [ -z "$ALL_SPACES_DATA" ]; then
  phase_begin phase_start
  ALL_SPACES_DATA="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
  phase_add PHASE_SPACES_MS "$phase_start"
fi
[ -n "$ALL_SPACES_DATA" ] || exit 0

phase_begin phase_start
load_space_item_lookup
phase_add PHASE_LOOKUP_MS "$phase_start"

[ "${#SPACE_ITEM_PRESENT[@]}" -gt 0 ] || exit 0
phase_begin phase_start
load_state_space_maps
phase_add PHASE_STATE_MS "$phase_start"

phase_begin phase_start
if prefetch_visible_space_apps; then
  phase_add PHASE_APP_MS "$phase_start"
  phase_begin phase_start
  prefetch_app_glyphs_for_loaded_spaces || true
  phase_add PHASE_GLYPH_MS "$phase_start"
else
  phase_add PHASE_APP_MS "$phase_start"
fi

declare -a FAST_ARGS=()
spaces_count=0
visible_count=0
focused_space_index=""
focused_display_index=""
app_phase_start=0
glyph_phase_start=0

phase_begin phase_start
load_cached_space_icons
while IFS=' ' read -r space_index space_display is_visible has_focus space_type; do
  [ -n "$space_index" ] || continue
  item="space.$space_index"
  [ "${SPACE_ITEM_PRESENT[$space_index]-0}" = "1" ] || continue

  spaces_count=$((spaces_count + 1))
  default_icon="${STATE_DEFAULT_ICONS[$space_index]-}"
  cached_icon="$(read_cached_icon "$space_index")"
  icon_value=""

  if [ -n "$default_icon" ]; then
    icon_value="$default_icon"
  else
    if [ "$is_visible" = "true" ]; then
      phase_begin app_phase_start
      app_name="$(resolve_visible_space_app "$space_index")"
      phase_add PHASE_APP_MS "$app_phase_start"
      if [ -n "$app_name" ]; then
        phase_begin glyph_phase_start
        icon_value="$(resolve_app_glyph "$app_name")"
        phase_add PHASE_GLYPH_MS "$glyph_phase_start"
        if [ -n "$icon_value" ]; then
          write_cached_icon "$space_index" "$icon_value"
        fi
      fi
    fi

    if [ -z "$icon_value" ] && [ -n "$cached_icon" ]; then
      icon_value="$cached_icon"
    fi
  fi

  if [ -z "$icon_value" ] && [ "$has_focus" = "true" ]; then
    icon_value="$ACTIVE_EMPTY_ICON"
  elif [ -z "$icon_value" ]; then
    icon_value="$EMPTY_ICON"
  fi

  if [ "$is_visible" = "true" ]; then
    visible_count=$((visible_count + 1))
  fi

  desired_mode="${STATE_SPACE_MODES[$space_index]-}"
  if [ "$is_visible" = "true" ] && [ -n "$desired_mode" ] && [ "$space_type" != "$desired_mode" ]; then
    "$YABAI_BIN" -m space "$space_index" --layout "$desired_mode" >/dev/null 2>&1 || true
  fi

  if [ "$has_focus" = "true" ]; then
    focused_space_index="$space_index"
    focused_display_index="$space_display"
    FAST_ARGS+=(--set "$item" icon="$icon_value")
    append_style_args "$item" focused
  elif [ "$is_visible" = "true" ]; then
    FAST_ARGS+=(--set "$item" icon="$icon_value")
    append_style_args "$item" visible
  else
    FAST_ARGS+=(--set "$item" icon="$icon_value")
    append_style_args "$item" idle
  fi
done < <(printf '%s\n' "$ALL_SPACES_DATA" | "$JQ_BIN" -r 'sort_by(.display, .index)[] | "\(.index) \(.display) \(.["is-visible"]) \(.["has-focus"] // false) \(.type // "unknown")"')
phase_add PHASE_LOOP_MS "$phase_start"

[ ${#FAST_ARGS[@]} -gt 0 ] || exit 0
phase_begin phase_start
if ! "$SKETCHYBAR_BIN" "${FAST_ARGS[@]}" >/dev/null 2>&1; then
  phase_add PHASE_APPLY_MS "$phase_start"
  invalidate_visual_recovery_state
  exit 1
fi
phase_add PHASE_APPLY_MS "$phase_start"

if [ -n "$focused_space_index" ] && [ -n "$focused_display_index" ]; then
  if ! write_last_selected_context "$focused_space_index" "$focused_display_index"; then
    invalidate_visual_recovery_state
    exit 1
  fi
else
  invalidate_selected_context
fi
mark_sender_refresh

record_perf "$START_MS" "$spaces_count" "$visible_count"
