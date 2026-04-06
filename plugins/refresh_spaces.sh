#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
CACHE_FILE="${CONFIG_DIR}/.spaces_cache"
ACTIVE_CACHE_FILE="${CONFIG_DIR}/.spaces_active_cache"
LOCK_DIR="${CONFIG_DIR}/.refresh_spaces.lock"
ICON_CACHE_DIR="${CONFIG_DIR}/cache/space_icons"
PERF_STATS_BIN="${CONFIG_DIR}/bin/barista-stats.sh"
SPACE_VISUALS_SCRIPT="${CONFIG_DIR}/plugins/space_visuals.sh"
BARISTA_REASON="${BARISTA_REASON:-}"
SPACE_METRICS_FILE=""
EXTERNAL_BAR_HEIGHT_CACHE_FILE="${CONFIG_DIR}/cache/external_bar_height"

create_metrics_file() {
  [ -n "$SPACE_METRICS_FILE" ] && return 0
  SPACE_METRICS_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-space-topology.XXXXXX")"
}

cleanup_metrics() {
  [ -n "$SPACE_METRICS_FILE" ] || return 0
  rm -f "$SPACE_METRICS_FILE" >/dev/null 2>&1 || true
}

update_external_bar_if_needed() {
  local bar_height="${1:-}"
  local cached_height=""
  local should_update=0

  [ -n "$bar_height" ] || return 0
  [ -x "$SCRIPTS_DIR/update_external_bar.sh" ] || return 0

  cached_height="$(cat "$EXTERNAL_BAR_HEIGHT_CACHE_FILE" 2>/dev/null || true)"
  if [ -z "$cached_height" ] || [ "$cached_height" != "$bar_height" ]; then
    should_update=1
  fi

  case "${SENDER:-${BARISTA_REASON:-}}" in
    display_changed|display_added|display_removed)
      should_update=1
      ;;
  esac

  if [ "$should_update" -eq 1 ]; then
    mkdir -p "$(dirname "$EXTERNAL_BAR_HEIGHT_CACHE_FILE")" 2>/dev/null || true
    "$SCRIPTS_DIR/update_external_bar.sh" "$bar_height"
    printf '%s' "$bar_height" > "$EXTERNAL_BAR_HEIGHT_CACHE_FILE" 2>/dev/null || true
  fi
}

now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf("%d\n", time() * 1000)'
    return
  fi
  date +%s | awk '{print $1 "000"}'
}

normalize_int() {
  case "${1:-}" in
    ''|*[!0-9-]*)
      printf '0'
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

START_MS="$(now_ms)"

record_perf() {
  local spaces_count="${1:-0}"
  [ -x "$PERF_STATS_BIN" ] || return 0
  local total_duration followup_duration topology_ms visual_call_ms
  local strategy="active_only"
  local added="0"
  local removed="0"
  local updated="0"
  local topology_ms="0"
  local prepare_ms="0"
  local apply_ms="0"
  local discovery_ms="0"
  local build_ms="0"
  local decision_ms="0"
  local visual_call_ms="${2:-0}"

  if [ -n "$SPACE_METRICS_FILE" ] && [ -f "$SPACE_METRICS_FILE" ]; then
    strategy="$(awk -F= '$1 == "strategy" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo full_rebuild)"
    added="$(awk -F= '$1 == "added" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    removed="$(awk -F= '$1 == "removed" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    updated="$(awk -F= '$1 == "updated" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    topology_ms="$(awk -F= '$1 == "topology_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    prepare_ms="$(awk -F= '$1 == "prepare_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    apply_ms="$(awk -F= '$1 == "apply_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    discovery_ms="$(awk -F= '$1 == "discovery_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    build_ms="$(awk -F= '$1 == "build_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
    decision_ms="$(awk -F= '$1 == "decision_ms" { print $2; exit }' "$SPACE_METRICS_FILE" 2>/dev/null || echo 0)"
  fi
  added="$(normalize_int "$added")"
  removed="$(normalize_int "$removed")"
  updated="$(normalize_int "$updated")"
  topology_ms="$(normalize_int "$topology_ms")"
  prepare_ms="$(normalize_int "$prepare_ms")"
  apply_ms="$(normalize_int "$apply_ms")"
  discovery_ms="$(normalize_int "$discovery_ms")"
  build_ms="$(normalize_int "$build_ms")"
  decision_ms="$(normalize_int "$decision_ms")"
  visual_call_ms="$(normalize_int "$visual_call_ms")"

  total_duration=$(( $(now_ms) - START_MS ))
  if [ "$total_duration" -lt 0 ]; then
    total_duration=0
  fi
  followup_duration=$((total_duration - topology_ms - visual_call_ms))
  if [ "$followup_duration" -lt 0 ]; then
    followup_duration=0
  fi

  if [ -n "$JQ_BIN" ]; then
    if [ "$topology_ms" -gt 0 ]; then
      BARISTA_EVENT_META_JSON="$("$JQ_BIN" -cn \
        --arg strategy "$strategy" \
        --argjson spaces "$spaces_count" \
        --argjson added "$added" \
        --argjson removed "$removed" \
        --argjson updated "$updated" \
        --argjson prepare_ms "$prepare_ms" \
        --argjson apply_ms "$apply_ms" \
        --argjson discovery_ms "$discovery_ms" \
        --argjson build_ms "$build_ms" \
        --argjson decision_ms "$decision_ms" \
        '{strategy: $strategy, spaces: $spaces, added: $added, removed: $removed, updated: $updated, prepare_ms: $prepare_ms, apply_ms: $apply_ms, discovery_ms: $discovery_ms, build_ms: $build_ms, decision_ms: $decision_ms}')" \
        "$PERF_STATS_BIN" event space_topology_refresh "$topology_ms" \
          "spaces=$spaces_count strategy=$strategy added=$added removed=$removed updated=$updated prepare_ms=$prepare_ms apply_ms=$apply_ms discovery_ms=$discovery_ms build_ms=$build_ms decision_ms=$decision_ms" >/dev/null 2>&1 || true
    fi
    BARISTA_EVENT_META_JSON="$("$JQ_BIN" -cn \
      --arg strategy "${strategy:-active_only}" \
      --argjson spaces "$spaces_count" \
      --argjson total_ms "$total_duration" \
      --argjson visual_call_ms "$visual_call_ms" \
      '{strategy: $strategy, spaces: $spaces, total_ms: $total_ms, visual_call_ms: $visual_call_ms}')" \
      "$PERF_STATS_BIN" event space_refresh_overhead "$followup_duration" \
        "spaces=$spaces_count strategy=${strategy:-active_only} total_ms=$total_duration visual_call_ms=$visual_call_ms" >/dev/null 2>&1 || true
  else
    if [ "$topology_ms" -gt 0 ]; then
      "$PERF_STATS_BIN" event space_topology_refresh "$topology_ms" \
        "spaces=$spaces_count strategy=$strategy added=$added removed=$removed updated=$updated prepare_ms=$prepare_ms apply_ms=$apply_ms discovery_ms=$discovery_ms build_ms=$build_ms decision_ms=$decision_ms" >/dev/null 2>&1 || true
    fi
    "$PERF_STATS_BIN" event space_refresh_overhead "$followup_duration" \
      "spaces=$spaces_count strategy=${strategy:-active_only} total_ms=$total_duration visual_call_ms=$visual_call_ms" >/dev/null 2>&1 || true
  fi
}

refresh_space_visuals() {
  local sender="${1:-space_visual_refresh}"
  local spaces_data="${2:-}"
  if [ -x "$SPACE_VISUALS_SCRIPT" ]; then
    NAME="space_runtime" SENDER="$sender" BARISTA_ALL_SPACES_DATA="$spaces_data" \
      "$SPACE_VISUALS_SCRIPT" >/dev/null 2>&1 || true
  else
    [ -n "$SKETCHYBAR_BIN" ] || return 0
    "$SKETCHYBAR_BIN" --trigger space_visual_refresh >/dev/null 2>&1 || true
  fi
}

trigger_space_mode_refresh() {
  [ -n "$SKETCHYBAR_BIN" ] || return 0
  "$SKETCHYBAR_BIN" --trigger space_mode_refresh >/dev/null 2>&1 || true
}

trigger_space_change_if_needed() {
  [ "$BARISTA_REASON" = "space_changed" ] || return 0
  [ -n "$SKETCHYBAR_BIN" ] || return 0
  "$SKETCHYBAR_BIN" --trigger space_change >/dev/null 2>&1 || true
}

space_items_present() {
  [ -n "${ALL_SPACES_DATA:-}" ] || return 1
  [ -n "$JQ_BIN" ] || return 1
  [ -n "$SKETCHYBAR_BIN" ] || return 1

  local bar_items found_space=0
  local space_index=""
  bar_items="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null | "$JQ_BIN" -r '.items[] | select(test("^space\\.[0-9]+$"))' 2>/dev/null || true)"
  [ -n "$bar_items" ] || return 1
  while IFS= read -r space_index; do
    [ -n "$space_index" ] || continue
    found_space=1
    if ! printf '%s\n' "$bar_items" | grep -Fxq "space.$space_index"; then
      return 1
    fi
  done < <(printf '%s' "$ALL_SPACES_DATA" | "$JQ_BIN" -r '.[].index // empty' 2>/dev/null)

  [ "$found_space" -eq 1 ]
}

# Simple lock to avoid overlapping refreshes from rapid display events
# Auto-recover stale locks older than 10 seconds (e.g. from killed processes)
if [ -d "$LOCK_DIR" ]; then
  lock_age=0
  if stat -f %m "$LOCK_DIR" >/dev/null 2>&1; then
    lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
    now=$(date +%s)
    lock_age=$((now - lock_mtime))
  fi
  if [ "$lock_age" -gt 10 ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
cleanup_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
  cleanup_metrics
}
trap cleanup_lock EXIT

# Skip work if neither display topology nor space mapping changed
# PERF: Single yabai query, derive all three signatures via jq
current_display_state=""
current_space_state=""
current_active_state=""
if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
  ALL_SPACES_DATA="$("$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
  if [ -n "$ALL_SPACES_DATA" ]; then
    current_display_state="$(printf '%s' "$ALL_SPACES_DATA" | "$JQ_BIN" -r '[.[].display] | unique | sort | join(",")' 2>/dev/null || true)"
    current_space_state="$(printf '%s' "$ALL_SPACES_DATA" | "$JQ_BIN" -r '[.[] | "\(.display)-\(.index)"] | sort | join(",")' 2>/dev/null || true)"
    current_active_state="$(printf '%s' "$ALL_SPACES_DATA" | "$JQ_BIN" -r '[.[] | select(."is-visible" == true) | "\(.display):\(.index)"] | sort | join(",")' 2>/dev/null || true)"
  fi
fi

if [ -n "$current_display_state$current_space_state" ]; then
  combined_state="${current_display_state}|${current_space_state}"
  cached_state="$(cat "$CACHE_FILE" 2>/dev/null || true)"
  if [ "$combined_state" = "$cached_state" ]; then
    if space_items_present; then
      spaces_count="$(printf '%s' "$ALL_SPACES_DATA" | "$JQ_BIN" -r 'length' 2>/dev/null || echo 0)"
      cached_active_state="$(cat "$ACTIVE_CACHE_FILE" 2>/dev/null || true)"
      if [ -n "$current_active_state" ] && [ "$current_active_state" != "$cached_active_state" ]; then
        printf '%s' "$current_active_state" >"$ACTIVE_CACHE_FILE" || true
        trigger_space_change_if_needed
        refresh_space_visuals "space_active_refresh" "$ALL_SPACES_DATA"
      fi
      record_perf "$spaces_count"
      exit 0
    fi
  fi
  cached_space_state=""
  case "$cached_state" in
    *"|"*) cached_space_state="${cached_state#*|}" ;;
  esac
  if [ -n "$cached_space_state" ] && [ "$cached_space_state" != "$current_space_state" ]; then
    if [ -d "$ICON_CACHE_DIR" ]; then
      rm -f "$ICON_CACHE_DIR"/* 2>/dev/null || true
    fi
  fi
  printf '%s' "$combined_state" >"$CACHE_FILE" || true
  printf '%s' "$current_active_state" >"$ACTIVE_CACHE_FILE" || true
fi

# OPTIMIZED: Removed sleep - the cache check above provides sufficient debouncing

create_metrics_file
BARISTA_SPACE_METRICS_FILE="$SPACE_METRICS_FILE" "$CONFIG_DIR/plugins/simple_spaces.sh"

trigger_space_change_if_needed
trigger_space_mode_refresh
visual_refresh_start_ms="$(now_ms)"
refresh_space_visuals "${SENDER:-${BARISTA_REASON:-space_topology_refresh}}" "${ALL_SPACES_DATA:-}"
visual_refresh_duration_ms=$(( $(now_ms) - visual_refresh_start_ms ))
if [ "$visual_refresh_duration_ms" -lt 0 ]; then
  visual_refresh_duration_ms=0
fi

spaces_count="$(printf '%s' "${ALL_SPACES_DATA:-[]}" | "$JQ_BIN" -r 'length' 2>/dev/null || echo 0)"
record_perf "$spaces_count" "$visual_refresh_duration_ms"

bar_height="${1:-}"
if [ -z "$bar_height" ] && [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
  bar_height=$("$JQ_BIN" -r '.appearance.bar_height // empty' "$STATE_FILE" 2>/dev/null || true)
fi
if [ -z "$bar_height" ] || [ "$bar_height" = "null" ]; then
  bar_height=28
fi
update_external_bar_if_needed "$bar_height"
