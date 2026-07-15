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
BARISTA_ALL_SPACES_DATA="${BARISTA_ALL_SPACES_DATA:-}"
STATE_FILE="${STATE_FILE:-$CONFIG_DIR/state.json}"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
APP_GLYPH_CACHE_DIR="$CONFIG_DIR/cache/app_glyphs"
APP_GLYPH_CACHE_VERSION="2"
APP_GLYPH_CACHE_VERSION_FILE="$APP_GLYPH_CACHE_DIR/.version"
SPACE_VISUALS_STATE_DIR="$CONFIG_DIR/cache/space_visuals"
SPACE_VISUALS_LOCK_DIR="$CONFIG_DIR/.space_visuals.lock"
SPACE_VISUALS_LOCK_STALE_SECONDS=5
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
STYLE_STATE_ROOT_CACHE=""
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

  STYLE_FOCUSED_PROPS="$(printf '%s\n' "${STYLE_FOCUSED_ARGS[@]}")"
  STYLE_VISIBLE_PROPS="$(printf '%s\n' "${STYLE_VISIBLE_ARGS[@]}")"
  STYLE_IDLE_PROPS="$(printf '%s\n' "${STYLE_IDLE_ARGS[@]}")"
}

cached_space_style_props() {
  init_cached_style_args
  case "${1:-idle}" in
    focused) printf '%s' "$STYLE_FOCUSED_PROPS" ;;
    visible) printf '%s' "$STYLE_VISIBLE_PROPS" ;;
    idle|*) printf '%s' "$STYLE_IDLE_PROPS" ;;
  esac
}

append_cached_style_args_to_fast() {
  init_cached_style_args
  case "${1:-idle}" in
    focused) FAST_ARGS+=("${STYLE_FOCUSED_ARGS[@]}") ;;
    visible) FAST_ARGS+=("${STYLE_VISIBLE_ARGS[@]}") ;;
    idle|*) FAST_ARGS+=("${STYLE_IDLE_ARGS[@]}") ;;
  esac
}

cached_style_state_root() {
  if [ -z "$STYLE_STATE_ROOT_CACHE" ]; then
    STYLE_STATE_ROOT_CACHE="$(space_style_state_root)"
  fi
  printf '%s' "$STYLE_STATE_ROOT_CACHE"
}

ensure_style_state_dir() {
  [ "$STYLE_STATE_DIR_READY" -eq 0 ] || return 0
  STYLE_STATE_DIR_READY=1
  mkdir -p "$(cached_style_state_root)" 2>/dev/null || true
}

style_state_file_for_item() {
  local item="${1:-}"
  local root
  [ -n "$item" ] || return 1
  root="$(cached_style_state_root)"
  case "$item" in
    *[!A-Za-z0-9._-]*)
      space_style_state_file "$item"
      ;;
    *)
      printf '%s/%s.state' "$root" "$item"
      ;;
  esac
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

phase_now() {
  if [ "$PHASE_METRICS_ENABLED" = "1" ]; then
    now_ms
  else
    printf '0'
  fi
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

append_style_args() {
  local item="${1:-}"
  local state="${2:-idle}"
  local style_props="" style_start_ms
  [ -n "$item" ] || return 0
  style_start_ms="$(phase_now)"
  style_props="$(cached_space_style_props "$state")"
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
  [ -n "$style_props" ] || style_props="$(cached_space_style_props "$state")"

  state_file="$(style_state_file_for_item "$item" 2>/dev/null || true)"
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

acquire_visual_lock() {
  local lock_age=0
  if [ -d "$SPACE_VISUALS_LOCK_DIR" ]; then
    if stat -f %m "$SPACE_VISUALS_LOCK_DIR" >/dev/null 2>&1; then
      local lock_mtime now
      lock_mtime=$(stat -f %m "$SPACE_VISUALS_LOCK_DIR" 2>/dev/null || echo 0)
      now=$(date +%s)
      lock_age=$((now - lock_mtime))
    fi
    if [ "$lock_age" -gt "$SPACE_VISUALS_LOCK_STALE_SECONDS" ]; then
      rmdir "$SPACE_VISUALS_LOCK_DIR" 2>/dev/null || true
    fi
  fi

  if mkdir "$SPACE_VISUALS_LOCK_DIR" 2>/dev/null; then
    trap 'rmdir "$SPACE_VISUALS_LOCK_DIR" 2>/dev/null || true' EXIT
    return 0
  fi

  return 1
}

should_skip_front_app_refresh() {
  local sender="${SENDER:-}"
  local last_authoritative last_front
  [ "$sender" = "front_app_switched" ] || return 1

  last_authoritative="$(read_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE")"
  if [ -n "$last_authoritative" ] && [ $((START_MS - last_authoritative)) -lt "$FRONT_APP_COOLDOWN_MS" ]; then
    return 0
  fi

  last_front="$(read_ms_file "$LAST_FRONT_APP_REFRESH_FILE")"
  if [ -n "$last_front" ] && [ $((START_MS - last_front)) -lt "$FRONT_APP_DEBOUNCE_MS" ]; then
    return 0
  fi

  return 1
}

should_skip_startup_sync() {
  local sender="${SENDER:-}"
  local last_authoritative
  [ "$sender" = "startup_sync" ] || return 1

  last_authoritative="$(read_ms_file "$LAST_AUTHORITATIVE_REFRESH_FILE")"
  [ -n "$last_authoritative" ] || return 1
  [ $((START_MS - last_authoritative)) -lt "$STARTUP_SYNC_COOLDOWN_MS" ]
}

mark_sender_refresh() {
  case "${SENDER:-}" in
    front_app_switched)
      write_ms_file "$LAST_FRONT_APP_REFRESH_FILE" "$START_MS"
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
  local app_name="" current_space_index="" current_space_visible="false"
  local item default_icon cached_icon icon_value last_selected_space
  local phase_start style_props focus_context_ms=0

  case "$sender" in
    front_app_switched|space_active_refresh)
      ;;
    *)
      return 1
      ;;
  esac
  [ -x "$FRONT_APP_CONTEXT_SCRIPT" ] || return 1
  [ -n "$SKETCHYBAR_BIN" ] || return 1

  phase_start="$(phase_now)"
  while IFS=$'\t' read -r key value; do
    case "$key" in
      app_name) app_name="$value" ;;
      space_index) current_space_index="$value" ;;
      space_visible) current_space_visible="$value" ;;
    esac
  done < <(
    if [ "$sender" = "front_app_switched" ] && [ -n "${INFO:-}" ]; then
      "$FRONT_APP_CONTEXT_SCRIPT" --mode focused-space --app "${INFO:-}" 2>/dev/null || true
    else
      "$FRONT_APP_CONTEXT_SCRIPT" --mode focused-space 2>/dev/null || true
    fi
  )
  if [ "$PHASE_METRICS_ENABLED" = "1" ]; then
    focus_context_ms=$(( $(now_ms) - phase_start ))
  fi

  [ -n "$app_name" ] || return 1
  [ -n "$current_space_index" ] || return 1
  [ "$current_space_visible" = "true" ] || return 1

  SPACE_VISUAL_PATH="focus"
  PHASE_SPACES_MS=$((PHASE_SPACES_MS + focus_context_ms))

  item="space.$current_space_index"
  phase_start="$(phase_now)"
  load_state_space_maps
  phase_add PHASE_STATE_MS "$phase_start"
  if [ ! -s "$SPACE_ITEM_LOOKUP_FILE" ]; then
    mkdir -p "$SPACE_VISUALS_STATE_DIR" 2>/dev/null || true
    printf '%s\n' "$item" > "$SPACE_ITEM_LOOKUP_FILE" 2>/dev/null || true
  fi
  phase_start="$(phase_now)"
  load_space_item_lookup
  phase_add PHASE_LOOKUP_MS "$phase_start"
  [ "${SPACE_ITEM_PRESENT[$current_space_index]-0}" = "1" ] || return 1

  default_icon="${STATE_DEFAULT_ICONS[$current_space_index]-}"
  cached_icon="$(read_cached_icon "$current_space_index")"
  if [ -n "$default_icon" ]; then
    icon_value="$default_icon"
  else
    phase_start="$(phase_now)"
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

  last_selected_space="$(read_ms_file "$LAST_SELECTED_SPACE_FILE")"
  if [ -n "$last_selected_space" ] && [ "$last_selected_space" != "$current_space_index" ] && [ "${SPACE_ITEM_PRESENT[$last_selected_space]-0}" = "1" ]; then
    local previous_args=()
    phase_start="$(phase_now)"
    init_cached_style_args
    style_props="$(cached_space_style_props idle)"
    remember_style_state "space.$last_selected_space" idle "$style_props"
    previous_args=("${STYLE_IDLE_ARGS[@]}")
    phase_add PHASE_STYLE_MS "$phase_start"
    phase_start="$(phase_now)"
    "$SKETCHYBAR_BIN" --set "space.$last_selected_space" "${previous_args[@]}" >/dev/null 2>&1 || true
    phase_add PHASE_APPLY_MS "$phase_start"
  fi

  local focused_args=()
  phase_start="$(phase_now)"
  init_cached_style_args
  style_props="$(cached_space_style_props focused)"
  remember_style_state "$item" focused "$style_props"
  focused_args=("${STYLE_FOCUSED_ARGS[@]}")
  phase_add PHASE_STYLE_MS "$phase_start"
  phase_start="$(phase_now)"
  "$SKETCHYBAR_BIN" --set "$item" icon="$icon_value" "${focused_args[@]}" >/dev/null 2>&1 || true
  phase_add PHASE_APPLY_MS "$phase_start"
  write_ms_file "$LAST_SELECTED_SPACE_FILE" "$current_space_index"

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

START_MS="$(now_ms)"

if [ "${SENDER:-}" = "forced" ]; then
  exit 0
fi

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

if ! acquire_visual_lock; then
  exit 0
fi

if should_skip_front_app_refresh; then
  exit 0
fi

if should_skip_startup_sync; then
  exit 0
fi

mark_sender_refresh

if refresh_single_visible_space_from_focus_context; then
  exit 0
fi

[ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || exit 0

ALL_SPACES_DATA="$BARISTA_ALL_SPACES_DATA"
if [ -z "$ALL_SPACES_DATA" ]; then
  phase_start="$(phase_now)"
  ALL_SPACES_DATA="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
  phase_add PHASE_SPACES_MS "$phase_start"
fi
[ -n "$ALL_SPACES_DATA" ] || exit 0

phase_start="$(phase_now)"
load_space_item_lookup
phase_add PHASE_LOOKUP_MS "$phase_start"

[ "${#SPACE_ITEM_PRESENT[@]}" -gt 0 ] || exit 0
phase_start="$(phase_now)"
load_state_space_maps
phase_add PHASE_STATE_MS "$phase_start"

phase_start="$(phase_now)"
if prefetch_visible_space_apps; then
  phase_add PHASE_APP_MS "$phase_start"
  phase_start="$(phase_now)"
  prefetch_app_glyphs_for_loaded_spaces || true
  phase_add PHASE_GLYPH_MS "$phase_start"
else
  phase_add PHASE_APP_MS "$phase_start"
fi

declare -a FAST_ARGS=()
spaces_count=0
visible_count=0
focused_space_index=""

phase_start="$(phase_now)"
while IFS=' ' read -r space_index _display is_visible has_focus space_type; do
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
      app_phase_start="$(phase_now)"
      app_name="$(resolve_visible_space_app "$space_index")"
      phase_add PHASE_APP_MS "$app_phase_start"
      if [ -n "$app_name" ]; then
        glyph_phase_start="$(phase_now)"
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

if [ ${#FAST_ARGS[@]} -gt 0 ]; then
  phase_start="$(phase_now)"
  "$SKETCHYBAR_BIN" "${FAST_ARGS[@]}" >/dev/null 2>&1 || true
  phase_add PHASE_APPLY_MS "$phase_start"
fi

if [ -n "$focused_space_index" ]; then
  write_ms_file "$LAST_SELECTED_SPACE_FILE" "$focused_space_index"
else
  rm -f "$LAST_SELECTED_SPACE_FILE" >/dev/null 2>&1 || true
fi

record_perf "$START_MS" "$spaces_count" "$visible_count"
