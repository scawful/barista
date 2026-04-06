#!/bin/bash

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
FOCUS_SCRIPT="$CONFIG_DIR/plugins/focus_space.sh"
ICON_CACHE_DIR="$CONFIG_DIR/cache/space_icons"
RETRY_FILE="$CONFIG_DIR/.spaces_retry"
SIG_CACHE_FILE="$CONFIG_DIR/.spaces_signatures"
STATE_FILE="$CONFIG_DIR/state.json"
SPACE_ACTION_SCRIPT="$CONFIG_DIR/scripts/space_action.sh"
SPACE_MANAGER_BIN="$CONFIG_DIR/bin/space_manager"
SPACE_METRICS_FILE="${BARISTA_SPACE_METRICS_FILE:-}"
# OPTIMIZED: Reduced retry attempts and delays for faster startup
MAX_SPACE_QUERY_ATTEMPTS=3
SPACE_QUERY_DELAY=0.05
SIMPLE_SPACES_START_MS=""
STATE_SPACE_CONFIG_LOADED=0
STATE_CREATOR_MODE=""
STATE_DIFF_UPDATES_ENABLED=""
BAR_QUERY_JSON=""
BAR_HEIGHT_SNAPSHOT=""
BAR_ITEMS_LOOKUP=""
BAR_SPACE_ITEM_COUNT=""
CACHED_SPACE_ICONS_LOADED=0
DISPLAY_STATE_LOADED=0
DISPLAY_COUNT_CACHE=""
ACTIVE_DISPLAY_CACHE=""
CACHED_SIGNATURES_LOADED=0
CACHED_TOPOLOGY=""
CACHED_CREATOR_TOPOLOGY=""
CACHED_SPACE_PROPS=""
CACHED_CREATOR_PROPS=""
FULL_REBUILD_DISCOVERY_END_MS=""
FULL_REBUILD_BUILD_END_MS=""
SPACE_ACTION_PREFIX=""
CREATOR_ACTION_PREFIX=""
CREATOR_ACTION_FALLBACK=""

declare -a CACHED_SPACE_ICONS

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

load_state_space_config() {
  [ "$STATE_SPACE_CONFIG_LOADED" -eq 0 ] || return 0
  STATE_SPACE_CONFIG_LOADED=1
  if [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
    local state_values=""
    state_values="$("$JQ_BIN" -r '[.spaces.creator_mode // "", (.spaces.experimental_diff_updates // "")] | @tsv' "$STATE_FILE" 2>/dev/null || true)"
    if [ -n "$state_values" ]; then
      IFS=$'\t' read -r STATE_CREATOR_MODE STATE_DIFF_UPDATES_ENABLED <<< "$state_values"
    fi
  fi
}

ensure_bar_snapshot_loaded() {
  [ -n "$BAR_ITEMS_SNAPSHOT" ] && return 0
  [ -n "$SKETCHYBAR_BIN" ] || return 0
  [ -n "$JQ_BIN" ] || return 0
  BAR_QUERY_JSON="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null || true)"
  [ -n "$BAR_QUERY_JSON" ] || return 0
  BAR_HEIGHT_SNAPSHOT=""
  BAR_ITEMS_SNAPSHOT=""
  local item line_type line_value
  local count=0
  while IFS=$'\t' read -r line_type line_value; do
    case "$line_type" in
      H)
        BAR_HEIGHT_SNAPSHOT="$line_value"
        ;;
      I)
        item="$line_value"
        if [ -n "$BAR_ITEMS_SNAPSHOT" ]; then
          BAR_ITEMS_SNAPSHOT+=$'\n'
        fi
        BAR_ITEMS_SNAPSHOT+="$item"
        ;;
      *)
        continue
        ;;
    esac
    case "${item:-}" in
      space.[0-9]*)
        count=$((count + 1))
        ;;
    esac
    item=""
  done < <(printf '%s' "$BAR_QUERY_JSON" | "$JQ_BIN" -r '("H\t" + ((.height // empty) | tostring)), (.items[]? | "I\t" + .)' 2>/dev/null || true)
  BAR_ITEMS_LOOKUP=$'\n'"$BAR_ITEMS_SNAPSHOT"$'\n'
  BAR_SPACE_ITEM_COUNT="$count"
}

load_display_state() {
  [ "$DISPLAY_STATE_LOADED" -eq 0 ] || return 0
  if [ -n "$DISPLAY_COUNT_CACHE" ] || [ -n "$ACTIVE_DISPLAY_CACHE" ]; then
    DISPLAY_STATE_LOADED=1
    return 0
  fi
  DISPLAY_STATE_LOADED=1
  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    local display_state_json=""
    local display_state_values=""
    display_state_json="$("$YABAI_BIN" -m query --displays 2>/dev/null || true)"
    if [ -n "$display_state_json" ]; then
      display_state_values="$(printf '%s' "$display_state_json" | "$JQ_BIN" -r '[(map(select(."has-focus" == true) | .index)[0] // .[0].index // empty | tostring), (length | tostring)] | @tsv' 2>/dev/null || true)"
      if [ -n "$display_state_values" ]; then
        IFS=$'\t' read -r ACTIVE_DISPLAY_CACHE DISPLAY_COUNT_CACHE <<< "$display_state_values"
      fi
    fi
  fi
  if [ -z "$DISPLAY_COUNT_CACHE" ] && [ -n "$SKETCHYBAR_BIN" ] && [ -n "$JQ_BIN" ]; then
    DISPLAY_COUNT_CACHE="$("$SKETCHYBAR_BIN" --query displays 2>/dev/null | "$JQ_BIN" -r 'length' 2>/dev/null || true)"
  fi
}

resolve_space_item_height() {
  local bar_height=""
  ensure_bar_snapshot_loaded
  if [ -n "$BAR_HEIGHT_SNAPSHOT" ]; then
    bar_height="$BAR_HEIGHT_SNAPSHOT"
  fi
  if [ -z "$bar_height" ] && [ -f "$STATE_FILE" ] && [ -n "$JQ_BIN" ]; then
    bar_height="$("$JQ_BIN" -r '.appearance.bar_height // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  if [ -z "$bar_height" ] || ! [ "$bar_height" -eq "$bar_height" ] 2>/dev/null; then
    bar_height=28
  fi

  local space_height=$((bar_height - 8))
  if [ "$space_height" -lt 20 ]; then
    space_height=20
  fi
  printf '%s' "$space_height"
}

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
  load_state_space_config
  normalize_creator_mode "${STATE_CREATOR_MODE:-per_display}"
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
  load_state_space_config
  local enabled="${STATE_DIFF_UPDATES_ENABLED:-true}"
  [ "$(normalize_bool "${enabled:-true}")" = "true" ]
}

initialize_action_prefixes() {
  if [ -x "$SPACE_ACTION_SCRIPT" ]; then
    SPACE_ACTION_PREFIX="$SPACE_ACTION_SCRIPT click --space "
    CREATOR_ACTION_PREFIX="$SPACE_ACTION_SCRIPT create --display "
    CREATOR_ACTION_FALLBACK=""
    return 0
  fi

  SPACE_ACTION_PREFIX=""
  CREATOR_ACTION_PREFIX=""
  if [ -x "$SPACE_MANAGER_BIN" ]; then
    CREATOR_ACTION_FALLBACK="$SPACE_MANAGER_BIN create"
    return 0
  fi
  CREATOR_ACTION_FALLBACK=""
}

space_click_action() {
  local space_index="${1:-}"
  if [ -n "$SPACE_ACTION_PREFIX" ]; then
    printf '%s%s' "$SPACE_ACTION_PREFIX" "$space_index"
    return 0
  fi
  printf '%s %s' "$FOCUS_SCRIPT" "$space_index"
}

creator_click_action() {
  local target_display="${1:-active}"
  if [ -n "$CREATOR_ACTION_PREFIX" ]; then
    printf '%s%s' "$CREATOR_ACTION_PREFIX" "$target_display"
    return 0
  fi
  if [ -n "$CREATOR_ACTION_FALLBACK" ]; then
    printf '%s' "$CREATOR_ACTION_FALLBACK"
    return 0
  fi
  printf '%s' 'yabai -m space --create'
}

item_exists() {
  local item="${1:-}"
  [ -n "$item" ] || return 1
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  "$SKETCHYBAR_BIN" --query "$item" >/dev/null 2>&1
}

BAR_ITEMS_SNAPSHOT=""

load_bar_items_snapshot() {
  ensure_bar_snapshot_loaded
}

snapshot_item_exists() {
  local item="${1:-}"
  [ -n "$item" ] || return 1
  [ -n "$BAR_ITEMS_LOOKUP" ] || return 1
  case "$BAR_ITEMS_LOOKUP" in
    *$'\n'"$item"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

snapshot_space_items() {
  [ -n "$BAR_ITEMS_SNAPSHOT" ] || return 0
  local item
  while IFS= read -r item; do
    case "$item" in
      space.[0-9]*)
        printf '%s\n' "$item"
        ;;
    esac
  done <<< "$BAR_ITEMS_SNAPSHOT"
}

count_snapshot_space_items() {
  if [ -n "$BAR_SPACE_ITEM_COUNT" ]; then
    printf '%s' "$BAR_SPACE_ITEM_COUNT"
    return 0
  fi
  printf '0'
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
    cache_value=""
    IFS= read -r cache_value < "$cache_file" || true
    [ -n "$cache_value" ] || continue
    CACHED_SPACE_ICONS[$cache_name]="$cache_value"
  done
  shopt -u nullglob
}

count_desired_space_items() {
  printf '%s' "${#SPACE_LINES[@]}"
}

write_space_metrics() {
  local strategy="${1:-unknown}"
  local added="${2:-0}"
  local removed="${3:-0}"
  local updated="${4:-0}"
  local prepare_ms="${5:-}"
  local apply_ms="${6:-}"
  local discovery_ms="${7:-}"
  local build_ms="${8:-}"
  local decision_ms="${9:-}"
  local topology_ms="0"
  [ -n "$SPACE_METRICS_FILE" ] || return 0
  if [ -n "$SIMPLE_SPACES_START_MS" ]; then
    topology_ms=$(( $(now_ms) - SIMPLE_SPACES_START_MS ))
    if [ "$topology_ms" -lt 0 ]; then
      topology_ms=0
    fi
  fi
  {
    printf 'strategy=%s\n' "$strategy"
    printf 'added=%s\n' "$added"
    printf 'removed=%s\n' "$removed"
    printf 'updated=%s\n' "$updated"
    printf 'topology_ms=%s\n' "$topology_ms"
    if [ -n "$prepare_ms" ]; then
      printf 'prepare_ms=%s\n' "$prepare_ms"
    fi
    if [ -n "$apply_ms" ]; then
      printf 'apply_ms=%s\n' "$apply_ms"
    fi
    if [ -n "$discovery_ms" ]; then
      printf 'discovery_ms=%s\n' "$discovery_ms"
    fi
    if [ -n "$build_ms" ]; then
      printf 'build_ms=%s\n' "$build_ms"
    fi
    if [ -n "$decision_ms" ]; then
      printf 'decision_ms=%s\n' "$decision_ms"
    fi
  } > "$SPACE_METRICS_FILE" 2>/dev/null || true
}

parse_spaces_payload() {
  local payload="${1:-}"
  local parse_output=""
  local record_type="" field1="" field2="" field3="" field4=""
  local display_ids_csv=""

  [ -n "$payload" ] || return 1
  [ -n "$JQ_BIN" ] || return 1

  parse_output="$(printf '%s\n' "$payload" | "$JQ_BIN" -r '
    . as $spaces
    | if (($spaces | type) != "array") or (($spaces | length) == 0) then
        empty
      else
        ("A\t" + (($spaces | map(select(."has-focus" == true) | .display | tostring)[0]) // "")),
        ("D\t" + ($spaces | map(.display | tostring) | unique | sort | join(","))),
        ($spaces | sort_by(.display, .index)[] | ["S", (.display | tostring), (.index | tostring), ((."is-visible" // false) | tostring), ((."has-focus" // false) | tostring)] | @tsv)
      end
  ' 2>/dev/null || true)"
  [ -n "$parse_output" ] || return 1

  SPACE_LINES=()
  DISPLAY_IDS=()
  VISIBLE_SPACE_LINES=()
  ACTIVE_DISPLAY_CACHE=""

  while IFS=$'\t' read -r record_type field1 field2 field3 field4; do
    case "$record_type" in
      A)
        ACTIVE_DISPLAY_CACHE="$field1"
        ;;
      D)
        display_ids_csv="$field1"
        if [ -n "$display_ids_csv" ]; then
          IFS=',' read -r -a DISPLAY_IDS <<< "$display_ids_csv"
        fi
        ;;
      S)
        [ -n "$field1" ] || continue
        SPACE_LINES+=("$field1 $field2")
        if [ "$field3" = "true" ]; then
          VISIBLE_SPACE_LINES+=("$field1 $field2")
        fi
        if [ "$field4" = "true" ] && [ -z "$ACTIVE_DISPLAY_CACHE" ]; then
          ACTIVE_DISPLAY_CACHE="$field1"
        fi
        ;;
    esac
  done <<< "$parse_output"

  [ "${#SPACE_LINES[@]}" -gt 0 ]
}

get_active_display() {
  load_display_state
  [ -n "$ACTIVE_DISPLAY_CACHE" ] || return 1
  printf '%s' "$ACTIVE_DISPLAY_CACHE"
}

get_display_count() {
  load_display_state
  [ -n "$DISPLAY_COUNT_CACHE" ] || return 1
  printf '%s' "$DISPLAY_COUNT_CACHE"
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
SPACE_ITEM_HEIGHT="$(resolve_space_item_height)"
SIMPLE_SPACES_START_MS="$(now_ms)"
initialize_action_prefixes

RAW_SPACES_DATA=""
SPACE_PARSE_OK=0
if [ -n "$YABAI_BIN" ]; then
  for ((attempt=1; attempt<=MAX_SPACE_QUERY_ATTEMPTS; attempt++)); do
    RAW_SPACES_DATA=$("$YABAI_BIN" -m query --spaces 2>/dev/null || true)
    if [ -n "$JQ_BIN" ] && parse_spaces_payload "$RAW_SPACES_DATA"; then
      SPACE_PARSE_OK=1
      break
    fi
    sleep "$SPACE_QUERY_DELAY"
  done
else
  echo "ERROR: yabai not found." >&2
  exit 1
fi

if [ "$SPACE_PARSE_OK" -ne 1 ]; then
  schedule_spaces_retry
  exit 0
fi
rm -f "$RETRY_FILE" 2>/dev/null || true

if [ ${#SPACE_LINES[@]} -eq 0 ]; then
  # Fallback if yabai returns nothing but runs
  DISPLAY_IDS=("1")
  for i in {1..10}; do
    SPACE_LINES+=("1 $i")
  done
fi

if [ -z "$DISPLAY_COUNT_CACHE" ]; then
  DISPLAY_COUNT_CACHE="${#DISPLAY_IDS[@]}"
fi

fallback_active=0
active_display="$(get_active_display || true)"
if [ -n "$active_display" ]; then
  active_display_present=0
  for display in "${DISPLAY_IDS[@]-}"; do
    if [ "$display" = "$active_display" ]; then
      active_display_present=1
      break
    fi
  done
  if [ "$active_display_present" -eq 0 ]; then
    fallback_active=1
  fi
fi
if [ "$fallback_active" -eq 0 ]; then
  display_count="$(get_display_count || true)"
  if [ -n "$display_count" ] && [ "${#DISPLAY_IDS[@]}" -lt "$display_count" ]; then
    fallback_active=1
  fi
fi
if [ "$fallback_active" -eq 1 ]; then
  schedule_spaces_retry
fi

load_bar_items_snapshot

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
  printf '%s\n' "${VISIBLE_SPACE_LINES[@]-}" | sed '/^$/d' | join_lines_with_comma
}

creator_targets_signature() {
  printf '%s\n' "${CREATOR_TARGETS[@]-}" | join_lines_with_comma
}

visible_by_display_signature() {
  local display visible out
  out=""
  for display in "${DISPLAY_IDS[@]-}"; do
    visible="$(visible_space_for_display "$display" || true)"
    [ -n "$visible" ] || continue
    if [ -n "$out" ]; then
      out="$out,$display:$visible"
    else
      out="$display:$visible"
    fi
  done
  printf '%s' "$out"
}

space_props_signature() {
  local entry display space_index space_display click_action
  for entry in "${SPACE_LINES[@]-}"; do
    display="${entry%% *}"
    space_index="${entry##* }"
    space_display="$display"
    if [ "$fallback_active" -eq 1 ]; then
      space_display="active"
    fi
    click_action="$(space_click_action "$space_index")"
    printf '%s|%s|%s|%s\n' "$space_index" "$space_display" "$SPACE_ITEM_HEIGHT" "$click_action"
  done | join_lines_with_comma
}

creator_props_signature() {
  local creator_target creator_item creator_cmd
  for creator_target in "${CREATOR_TARGETS[@]-}"; do
    creator_item="space_creator"
    if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
      creator_item="space_creator.$creator_target"
    fi
    creator_cmd="$(creator_click_action "$creator_target")"
    printf '%s|%s|%s|%s\n' \
      "$creator_item" "$creator_target" "$SPACE_ITEM_HEIGHT" "$creator_cmd"
  done | join_lines_with_comma
}

load_cached_signatures() {
  [ "$CACHED_SIGNATURES_LOADED" -eq 0 ] || return 0
  CACHED_SIGNATURES_LOADED=1
  [ -f "$SIG_CACHE_FILE" ] || return 0
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      topology) CACHED_TOPOLOGY="$value" ;;
      creator_topology) CACHED_CREATOR_TOPOLOGY="$value" ;;
      space_props) CACHED_SPACE_PROPS="$value" ;;
      creator_props) CACHED_CREATOR_PROPS="$value" ;;
    esac
  done < "$SIG_CACHE_FILE"
}

write_signatures() {
  local topology="$1"
  local creator_topology_sig="$2"
  local visible="$3"
  local visible_by_display="$4"
  local active_display_sig="$5"
  local space_props_sig="${6:-}"
  local creator_props_sig="${7:-}"
  {
    printf 'topology=%s\n' "$topology"
    printf 'creator_topology=%s\n' "$creator_topology_sig"
    printf 'visible=%s\n' "$visible"
    printf 'visible_by_display=%s\n' "$visible_by_display"
    printf 'active_display=%s\n' "$active_display_sig"
    printf 'space_props=%s\n' "$space_props_sig"
    printf 'creator_props=%s\n' "$creator_props_sig"
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

FULL_REBUILD_DISCOVERY_END_MS="$(now_ms)"
load_cached_space_icons

rebuild_creator_items_only() {
  local anchor_item="${1:-}"
  local last_creator="$anchor_item"
  local creator_target creator_item creator_cmd
  local -a creator_args=()

  "$SKETCHYBAR_BIN" --remove '/space_creator\..*/' --remove space_creator >/dev/null 2>&1 || true

  for creator_target in "${CREATOR_TARGETS[@]-}"; do
    creator_item="space_creator"
    if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
      creator_item="space_creator.$creator_target"
    fi
    creator_cmd="$(creator_click_action "$creator_target")"

    creator_args+=(--add item "$creator_item" left)
    creator_args+=(--set "$creator_item"
      display="$creator_target"
      ignore_association="on"
      icon="󰐕"
      icon.color="0x80a6adc8"
      icon.padding_left=8
      icon.padding_right=8
      label=""
      label.drawing=off
      background.drawing=off
      background.color="0x00000000"
      background.corner_radius=8
      background.height="$SPACE_ITEM_HEIGHT"
      script="$CONFIG_DIR/plugins/space_creator.sh"
      click_script="$creator_cmd")
    creator_args+=(--subscribe "$creator_item" mouse.entered mouse.exited)
    if [ -n "$last_creator" ]; then
      creator_args+=(--move "$creator_item" after "$last_creator")
    fi
    last_creator="$creator_item"
  done

  if [ ${#creator_args[@]} -gt 0 ]; then
    "$SKETCHYBAR_BIN" "${creator_args[@]}" >/dev/null 2>&1 || true
  fi
}

apply_incremental_space_items() {
  local anchor_item="${1:-}"
  local last_item="$anchor_item"
  local existing_item entry display space_index item space_display icon cached_icon click_action
  local -a update_args=()
  local added_count=0 removed_count=0 updated_count=0 strategy="incremental_reorder"

  while IFS= read -r existing_item; do
    [ -n "$existing_item" ] || continue
    case " ${SPACE_ITEMS[*]} " in
      *" $existing_item "*) ;;
      *)
        update_args+=(--remove "$existing_item")
        removed_count=$((removed_count + 1))
        strategy="incremental_add_remove"
        ;;
    esac
  done < <(snapshot_space_items)

  for entry in "${SPACE_LINES[@]-}"; do
    display="${entry%% *}"
    space_index="${entry##* }"
    item="space.$space_index"
    space_display="$display"
    if [ "$fallback_active" -eq 1 ]; then
      space_display="active"
    fi

    icon="$space_index"
    cached_icon="${CACHED_SPACE_ICONS[$space_index]-}"
    if [ -n "$cached_icon" ]; then
      icon="$cached_icon"
    fi
    click_action="$(space_click_action "$space_index")"

    if snapshot_item_exists "$item"; then
      update_args+=(--set "$item"
        space="$space_index"
        display="$space_display"
        associated_display="$space_display"
        associated_space="$space_index"
        ignore_association=off
        icon="$icon"
        icon.padding_left=6
        icon.padding_right=6
        icon.color=0xffcdd6f4
        label=""
        label.drawing=off
        label.color=0xffa6adc8
        label.padding_left=2
        label.padding_right=2
        background.drawing=off
        background.color=0x00000000
        background.corner_radius=8
        background.height="$SPACE_ITEM_HEIGHT"
        script="$CONFIG_DIR/plugins/space.sh"
        click_script="$click_action")
      updated_count=$((updated_count + 1))
    else
      update_args+=(--add space "$item" left)
      update_args+=(--set "$item"
        space="$space_index"
        display="$space_display"
        associated_display="$space_display"
        associated_space="$space_index"
        ignore_association=off
        icon="$icon"
        icon.padding_left=6
        icon.padding_right=6
        icon.color=0xffcdd6f4
        label=""
        label.drawing=off
        label.color=0xffa6adc8
        label.padding_left=2
        label.padding_right=2
        background.drawing=off
        background.color=0x00000000
        background.corner_radius=8
        background.height="$SPACE_ITEM_HEIGHT"
        script="$CONFIG_DIR/plugins/space.sh"
        click_script="$click_action")
      update_args+=(--subscribe "$item" mouse.entered mouse.exited)
      added_count=$((added_count + 1))
      updated_count=$((updated_count + 1))
      strategy="incremental_add_remove"
    fi
    if [ -n "$last_item" ]; then
      update_args+=(--move "$item" after "$last_item")
    fi
    last_item="$item"
  done

  if [ ${#update_args[@]} -gt 0 ]; then
    "$SKETCHYBAR_BIN" "${update_args[@]}" >/dev/null 2>&1 || true
  fi

  write_space_metrics "$strategy" "$added_count" "$removed_count" "$updated_count"
}

# Prepare batch command
declare -a SB_ARGS=()
SNAPSHOT_SPACE_COUNT="$(count_snapshot_space_items)"
FORCE_FULL_REBUILD=0
if [ "$SNAPSHOT_SPACE_COUNT" -eq 0 ]; then
  FORCE_FULL_REBUILD=1
fi

# Do not block startup waiting for front_app. If it is not present yet, fall
# back to the next available anchor and let the async reorder path repair the
# final placement once front_app appears.
anchor_item="front_app"
needs_front_app_reorder=0
if ! snapshot_item_exists "$anchor_item"; then
  needs_front_app_reorder=1
  if snapshot_item_exists "apple_menu"; then
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
  cached_icon="${CACHED_SPACE_ICONS[$space_index]-}"
  if [ -n "$cached_icon" ]; then
    icon="$cached_icon"
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
                          background.height="$SPACE_ITEM_HEIGHT" \
                          script="$CONFIG_DIR/plugins/space.sh" \
                          click_script="$click_action")
  SB_ARGS+=(--subscribe "$item" mouse.entered mouse.exited)

  if [ -n "$last_item" ]; then
    SB_ARGS+=(--move "$item" after "$last_item")
  fi
  
  last_item="$item"
  SPACE_ITEMS+=("$item")
done

FULL_REBUILD_BUILD_END_MS="$(now_ms)"

# Add space creator button(s)
PRIMARY_DISPLAY="${active_display:-1}"

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

SPACE_TOPOLOGY_SIG=""
CREATOR_TOPOLOGY_SIG=""
VISIBLE_SIG=""
VISIBLE_BY_DISPLAY_SIG=""
ACTIVE_DISPLAY_SIG=""
SPACE_PROPS_SIG=""
CREATOR_PROPS_SIG=""

compute_signatures() {
  SPACE_TOPOLOGY_SIG="$(topology_signature)"
  CREATOR_TOPOLOGY_SIG="creator_mode=$CREATOR_MODE|creator_targets=$(creator_targets_signature)"
  VISIBLE_SIG="$(visible_signature)"
  VISIBLE_BY_DISPLAY_SIG="$(visible_by_display_signature)"
  ACTIVE_DISPLAY_SIG="${active_display:-none}"
  SPACE_PROPS_SIG="$(space_props_signature)"
  CREATOR_PROPS_SIG="$(creator_props_signature)"
}

if [ "$DIFF_UPDATES_ENABLED" -eq 1 ] && [ "$FORCE_FULL_REBUILD" -eq 0 ]; then
  compute_signatures
  load_cached_signatures
  cached_topology="$CACHED_TOPOLOGY"
  cached_creator_topology="$CACHED_CREATOR_TOPOLOGY"
  cached_space_props="$CACHED_SPACE_PROPS"
  cached_creator_props="$CACHED_CREATOR_PROPS"
  if [ -n "$cached_topology" ] && [ "$cached_topology" = "$SPACE_TOPOLOGY_SIG" ]; then
    fast_path_ok=1
    for entry in "${SPACE_LINES[@]-}"; do
      space_index="${entry##* }"
      if ! snapshot_item_exists "space.$space_index"; then
        fast_path_ok=0
        break
      fi
      if [ "$fast_path_ok" -eq 0 ]; then
        break
      fi
    done

    if [ "$fast_path_ok" -eq 1 ]; then
      declare -a FAST_ARGS=()
      space_props_changed=0
      creator_props_changed=0
      creator_topology_matches=0
      creator_items_present=1

      if [ "$cached_space_props" != "$SPACE_PROPS_SIG" ]; then
        space_props_changed=1
      fi

      if [ "$cached_creator_props" != "$CREATOR_PROPS_SIG" ]; then
        creator_props_changed=1
      fi

      if [ -n "$cached_creator_topology" ] && [ "$cached_creator_topology" = "$CREATOR_TOPOLOGY_SIG" ]; then
        creator_topology_matches=1
      fi

      if [ "$creator_topology_matches" -eq 1 ]; then
        for creator_target in "${CREATOR_TARGETS[@]-}"; do
          creator_item="space_creator"
          if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
            creator_item="space_creator.$creator_target"
          fi
          if ! snapshot_item_exists "$creator_item"; then
            creator_items_present=0
            break
          fi
        done
      else
        creator_items_present=0
      fi

      if [ "$space_props_changed" -eq 1 ]; then
        for entry in "${SPACE_LINES[@]-}"; do
          space_index="${entry##* }"
          click_action="$(space_click_action "$space_index")"
          FAST_ARGS+=(--set "space.$space_index"
            click_script="$click_action"
            background.height="$SPACE_ITEM_HEIGHT")
        done
      fi

      if [ "$creator_items_present" -eq 1 ]; then
        if [ "$creator_props_changed" -eq 1 ]; then
          for creator_target in "${CREATOR_TARGETS[@]-}"; do
            creator_item="space_creator"
            if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
              creator_item="space_creator.$creator_target"
            fi
            creator_cmd="$(creator_click_action "$creator_target")"
            FAST_ARGS+=(--set "$creator_item"
              display="$creator_target"
              ignore_association="on"
              click_script="$creator_cmd"
              background.height="$SPACE_ITEM_HEIGHT")
          done
        fi
      else
        if [ ${#FAST_ARGS[@]} -gt 0 ]; then
          "$SKETCHYBAR_BIN" "${FAST_ARGS[@]}" >/dev/null 2>&1 || true
          FAST_ARGS=()
        fi
        rebuild_creator_items_only "${SPACE_ITEMS[${#SPACE_ITEMS[@]}-1]}"
        write_space_metrics "creator_only" 0 0 0
        write_signatures "$SPACE_TOPOLOGY_SIG" "$CREATOR_TOPOLOGY_SIG" "$VISIBLE_SIG" "$VISIBLE_BY_DISPLAY_SIG" "$ACTIVE_DISPLAY_SIG" "$SPACE_PROPS_SIG" "$CREATOR_PROPS_SIG"
        exit 0
      fi

      if [ ${#FAST_ARGS[@]} -gt 0 ]; then
        "$SKETCHYBAR_BIN" "${FAST_ARGS[@]}" >/dev/null 2>&1 || true
      fi

      if [ "$space_props_changed" -eq 1 ]; then
        write_space_metrics "props_only" 0 0 "$(count_desired_space_items)"
      else
        write_space_metrics "noop" 0 0 0
      fi

      write_signatures "$SPACE_TOPOLOGY_SIG" "$CREATOR_TOPOLOGY_SIG" "$VISIBLE_SIG" "$VISIBLE_BY_DISPLAY_SIG" "$ACTIVE_DISPLAY_SIG" "$SPACE_PROPS_SIG" "$CREATOR_PROPS_SIG"
      exit 0
    fi
  fi

  if [ -n "$cached_topology" ] && [ "$cached_topology" != "$SPACE_TOPOLOGY_SIG" ]; then
    apply_incremental_space_items "$anchor_item"
    rebuild_creator_items_only "${SPACE_ITEMS[${#SPACE_ITEMS[@]}-1]}"
    write_signatures "$SPACE_TOPOLOGY_SIG" "$CREATOR_TOPOLOGY_SIG" "$VISIBLE_SIG" "$VISIBLE_BY_DISPLAY_SIG" "$ACTIVE_DISPLAY_SIG" "$SPACE_PROPS_SIG" "$CREATOR_PROPS_SIG"
    exit 0
  fi
fi

declare -a CREATOR_ITEMS=()
for creator_target in "${CREATOR_TARGETS[@]-}"; do
  creator_item="space_creator"
  if [ "$CREATOR_MODE" = "per_display" ] && [ "$creator_target" != "active" ]; then
    creator_item="space_creator.$creator_target"
  fi
  creator_cmd="$(creator_click_action "$creator_target")"

  SB_ARGS+=(--add item "$creator_item" left)
  SB_ARGS+=(--set "$creator_item" \
                  display="$creator_target" \
                  ignore_association="on" \
                  icon="󰐕" \
                  icon.color="0x80a6adc8" \
                  icon.padding_left=8 \
                  icon.padding_right=8 \
                  label="" \
                  label.drawing=off \
                  background.drawing=off \
                  background.color="0x00000000" \
                  background.corner_radius=8 \
                  background.height="$SPACE_ITEM_HEIGHT" \
                  script="$CONFIG_DIR/plugins/space_creator.sh" \
                  click_script="$creator_cmd")
  SB_ARGS+=(--subscribe "$creator_item" mouse.entered mouse.exited)
  if [ -n "$last_item" ]; then
    SB_ARGS+=(--move "$creator_item" after "$last_item")
  fi
  last_item="$creator_item"
  CREATOR_ITEMS+=("$creator_item")
done

# PERF: Single batched remove call for full rebuild path
existing_space_count="$(count_snapshot_space_items)"
full_rebuild_apply_start_ms="$(now_ms)"
"$SKETCHYBAR_BIN" --remove '/space\..*/' --remove '/spaces\..*/' --remove '/space_creator\..*/' --remove space_creator >/dev/null 2>&1 || true

# Execute all commands in one single call
"$SKETCHYBAR_BIN" "${SB_ARGS[@]}"
full_rebuild_apply_end_ms="$(now_ms)"
full_rebuild_prepare_ms=$((full_rebuild_apply_start_ms - SIMPLE_SPACES_START_MS))
full_rebuild_apply_ms=$((full_rebuild_apply_end_ms - full_rebuild_apply_start_ms))
full_rebuild_discovery_ms=$((FULL_REBUILD_DISCOVERY_END_MS - SIMPLE_SPACES_START_MS))
full_rebuild_build_ms=$((FULL_REBUILD_BUILD_END_MS - FULL_REBUILD_DISCOVERY_END_MS))
full_rebuild_decision_ms=$((full_rebuild_apply_start_ms - FULL_REBUILD_BUILD_END_MS))
if [ -z "$SPACE_TOPOLOGY_SIG" ]; then
  compute_signatures
fi
write_space_metrics "full_rebuild" "$(count_desired_space_items)" "$existing_space_count" "$(count_desired_space_items)" "$full_rebuild_prepare_ms" "$full_rebuild_apply_ms" "$full_rebuild_discovery_ms" "$full_rebuild_build_ms" "$full_rebuild_decision_ms"
write_signatures "$SPACE_TOPOLOGY_SIG" "$CREATOR_TOPOLOGY_SIG" "$VISIBLE_SIG" "$VISIBLE_BY_DISPLAY_SIG" "$ACTIVE_DISPLAY_SIG" "$SPACE_PROPS_SIG" "$CREATOR_PROPS_SIG"


# If front_app wasn't ready yet, reorder spaces once it appears.
if [ "$needs_front_app_reorder" -eq 1 ]; then
  (
    for i in {1..30}; do
      if item_exists "front_app"; then
        # PERF: Batch all reorder moves into a single sketchybar call
        declare -a REORDER_ARGS=()
        last="front_app"
        for space_item in "${SPACE_ITEMS[@]}"; do
          REORDER_ARGS+=(--move "$space_item" after "$last")
          last="$space_item"
        done
        for creator_item in "${CREATOR_ITEMS[@]-}"; do
          REORDER_ARGS+=(--move "$creator_item" after "$last")
          last="$creator_item"
        done
        if [ ${#REORDER_ARGS[@]} -gt 0 ]; then
          "$SKETCHYBAR_BIN" "${REORDER_ARGS[@]}" >/dev/null 2>&1 || true
        fi
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
