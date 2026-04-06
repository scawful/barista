#!/bin/bash

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
PERF_STATS_BIN="$CONFIG_DIR/bin/barista-stats.sh"
ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
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

declare -a STATE_DEFAULT_ICONS
declare -a STATE_SPACE_MODES
declare -a CACHED_SPACE_ICONS
declare -a SPACE_APP_BY_INDEX
declare -a SPACE_APP_LOADED
declare -a SPACE_ITEM_PRESENT

IDLE_BG="0x00000000"
SELECTED_BG="0xFFcba6f7"
IDLE_ICON_COLOR="0xFFa6adc8"
SELECTED_ICON_COLOR="0xFF11111b"
EMPTY_ICON="○"
ACTIVE_EMPTY_ICON="•"
LAST_SELECTED_SPACE_FILE="$SPACE_VISUALS_STATE_DIR/last_selected_space"

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
  [ -n "$start_ms" ] || return 0
  [ -x "$PERF_STATS_BIN" ] || return 0
  local end_ms duration
  end_ms="$(now_ms)"
  duration=$((end_ms - start_ms))
  "$PERF_STATS_BIN" event space_visual_refresh "$duration" \
    "sender=${SENDER:-manual} spaces=$spaces_count visible=$visible_count" >/dev/null 2>&1 || true
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
  current_version="$(cat "$APP_GLYPH_CACHE_VERSION_FILE" 2>/dev/null || true)"
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

refresh_single_visible_space_from_focus_context() {
  local sender="${SENDER:-}"
  local app_name="" current_space_index="" current_space_visible="false"
  local item default_icon cached_icon icon_value last_selected_space

  case "$sender" in
    front_app_switched|space_active_refresh)
      ;;
    *)
      return 1
      ;;
  esac
  [ -x "$FRONT_APP_CONTEXT_SCRIPT" ] || return 1
  [ -n "$SKETCHYBAR_BIN" ] || return 1

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

  [ -n "$app_name" ] || return 1
  [ -n "$current_space_index" ] || return 1
  [ "$current_space_visible" = "true" ] || return 1

  item="space.$current_space_index"
  load_state_space_maps
  load_space_item_lookup
  [ "${SPACE_ITEM_PRESENT[$current_space_index]-0}" = "1" ] || return 1

  default_icon="${STATE_DEFAULT_ICONS[$current_space_index]-}"
  cached_icon="$(read_cached_icon "$current_space_index")"
  if [ -n "$default_icon" ]; then
    icon_value="$default_icon"
  else
    icon_value="$(resolve_app_glyph "$app_name")"
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
    "$SKETCHYBAR_BIN" --set "space.$last_selected_space" \
      background.drawing=off \
      background.color="$IDLE_BG" \
      icon.color="$IDLE_ICON_COLOR" >/dev/null 2>&1 || true
  fi

  "$SKETCHYBAR_BIN" --set "$item" \
    icon="$icon_value" \
    label.drawing=off \
    background.drawing=on \
    background.color="$SELECTED_BG" \
    icon.color="$SELECTED_ICON_COLOR" >/dev/null 2>&1 || true
  write_ms_file "$LAST_SELECTED_SPACE_FILE" "$current_space_index"

  record_perf "$START_MS" "1" "1"
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

  local item_name space_index refresh_lookup=0
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
    if [ -n "$BARISTA_ALL_SPACES_DATA" ] && [ "${SENDER:-}" != "manual" ] && [ "${SENDER:-}" != "startup_sync" ] && [ "${SENDER:-}" != "space_visual_refresh" ]; then
      printf '%s\n' "$BARISTA_ALL_SPACES_DATA" | "$JQ_BIN" -r '.[] | select(.index != null) | "space.\(.index)"' \
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
  ALL_SPACES_DATA="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
fi
[ -n "$ALL_SPACES_DATA" ] || exit 0

load_space_item_lookup

[ "${#SPACE_ITEM_PRESENT[@]}" -gt 0 ] || exit 0
load_state_space_maps

declare -a FAST_ARGS=()
spaces_count=0
visible_count=0
focused_space_index=""

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
      app_name="$(resolve_visible_space_app "$space_index")"
      if [ -n "$app_name" ]; then
        icon_value="$(resolve_app_glyph "$app_name")"
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
    FAST_ARGS+=(--set "$item"
      icon="$icon_value"
      label.drawing=off
      background.drawing=on
      background.color="$SELECTED_BG"
      icon.color="$SELECTED_ICON_COLOR")
  else
    FAST_ARGS+=(--set "$item"
      icon="$icon_value"
      label.drawing=off
      background.drawing=off
      background.color="$IDLE_BG"
      icon.color="$IDLE_ICON_COLOR")
  fi
done < <(printf '%s\n' "$ALL_SPACES_DATA" | "$JQ_BIN" -r 'sort_by(.display, .index)[] | "\(.index) \(.display) \(.["is-visible"]) \(.["has-focus"] // false) \(.type // "unknown")"')

if [ ${#FAST_ARGS[@]} -gt 0 ]; then
  "$SKETCHYBAR_BIN" "${FAST_ARGS[@]}" >/dev/null 2>&1 || true
fi

if [ -n "$focused_space_index" ]; then
  write_ms_file "$LAST_SELECTED_SPACE_FILE" "$focused_space_index"
else
  rm -f "$LAST_SELECTED_SPACE_FILE" >/dev/null 2>&1 || true
fi

record_perf "$START_MS" "$spaces_count" "$visible_count"
