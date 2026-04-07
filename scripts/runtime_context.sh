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
SWITCH_AUDIO_SOURCE_BIN="${BARISTA_SWITCH_AUDIO_SOURCE_BIN:-$(command -v SwitchAudioSource 2>/dev/null || true)}"
STATE_DIR="${BARISTA_RUNTIME_CONTEXT_DIR:-$CONFIG_DIR/cache/runtime_context}"
FRONT_APP_FILE="$STATE_DIR/front_app.tsv"
MEDIA_FILE="$STATE_DIR/media.tsv"
OUTPUTS_FILE="$STATE_DIR/outputs.tsv"
INTERVAL_SECONDS="${BARISTA_RUNTIME_CONTEXT_INTERVAL:-1}"
RUNTIME_CONTEXT_HELPER_BIN="${BARISTA_RUNTIME_CONTEXT_HELPER_BIN:-$CONFIG_DIR/bin/runtime_context_helper}"

usage() {
  cat >&2 <<'USAGE'
Usage: runtime_context.sh <command>
  refresh [front-app|media]
  daemon
  front-app
  focused-space
  media-status
  outputs
  switch-output <index>
USAGE
}

emit_line() {
  printf '%s\t%s\n' "$1" "$2"
}

runtime_context_helper_available() {
  [ -x "$RUNTIME_CONTEXT_HELPER_BIN" ]
}

run_runtime_context_helper() {
  runtime_context_helper_available || return 1
  BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
    BARISTA_YABAI_BIN="$YABAI_BIN" \
    BARISTA_RUNTIME_CONTEXT_INTERVAL="$INTERVAL_SECONDS" \
    "$RUNTIME_CONTEXT_HELPER_BIN" "$@"
}

lowercase_value() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

canonical_front_app_name() {
  local app_name="${1:-}"
  local current_space_json current_space_index current_display_index window_json window_app fallback_name

  [ -n "$app_name" ] || return 0

  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    current_space_json="$(query_current_space_json)"
    current_space_index="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.index // 0' 2>/dev/null || echo 0)"
    current_display_index="$(printf '%s\n' "$current_space_json" | "$JQ_BIN" -r '.display // 0' 2>/dev/null || echo 0)"
    window_json="$(select_matching_window_json "$app_name" "$current_space_index" "$current_display_index")"
    window_app="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.app // empty' 2>/dev/null || true)"
    if [ -n "$window_app" ] && [ "$(lowercase_value "$window_app")" = "$(lowercase_value "$app_name")" ]; then
      printf '%s' "$window_app"
      return 0
    fi
  fi

  fallback_name="$(resolve_front_app_name)"
  if [ -n "$fallback_name" ] && [ "$(lowercase_value "$fallback_name")" = "$(lowercase_value "$app_name")" ]; then
    printf '%s' "$fallback_name"
    return 0
  fi

  printf '%s' "$app_name"
}

normalize_front_app_output() {
  local output="${1:-}"
  local runtime_app_name canonical_name

  [ -n "$output" ] || return 0
  runtime_app_name="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "app_name" { print $2; exit }')"
  [ -n "$runtime_app_name" ] || {
    printf '%s\n' "$output"
    return 0
  }

  canonical_name="$(canonical_front_app_name "$runtime_app_name")"
  if [ -n "$canonical_name" ] && [ "$(lowercase_value "$runtime_app_name")" = "$(lowercase_value "$canonical_name")" ]; then
    printf '%s\n' "$output" | awk -F'\t' -v OFS='\t' -v canonical="$canonical_name" '
      $1 == "app_name" { $2 = canonical }
      { print }
    '
    return 0
  fi

  printf '%s\n' "$output"
}

normalize_front_app_cache_file() {
  [ -s "$FRONT_APP_FILE" ] || return 0
  local normalized
  normalized="$(normalize_front_app_output "$(cat "$FRONT_APP_FILE")")"
  printf '%s\n' "$normalized" | write_atomic "$FRONT_APP_FILE"
}

write_atomic() {
  local target="$1"
  local temp_file
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  temp_file="$(mktemp "$STATE_DIR/.tmp.XXXXXX")"
  cat > "$temp_file"
  mv "$temp_file" "$target"
}

refresh_front_app_cache() {
  if runtime_context_helper_available; then
    if run_runtime_context_helper refresh-front-app >/dev/null 2>&1; then
      normalize_front_app_cache_file
      return 0
    fi
  fi
  write_front_app_cache
}

osascript_safe() {
  [ -n "$OSASCRIPT_BIN" ] || return 0
  "$OSASCRIPT_BIN" "$@" 2>/dev/null || true
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

current_output_name() {
  local output_name=""
  if [ -n "$SWITCH_AUDIO_SOURCE_BIN" ]; then
    output_name="$($SWITCH_AUDIO_SOURCE_BIN -c -t output 2>/dev/null || true)"
    if [ -z "$output_name" ]; then
      output_name="$($SWITCH_AUDIO_SOURCE_BIN -a -t output 2>/dev/null | sed -n '1p' || true)"
    fi
  fi
  printf '%s' "$output_name"
}

resolve_front_app_name() {
  local app_name=""
  if [ -n "$OSASCRIPT_BIN" ]; then
    app_name="$(osascript_safe -e 'tell application "System Events" to name of first process whose frontmost is true')"
    if [ -n "$app_name" ]; then
      printf '%s' "$app_name"
      return 0
    fi
  fi

  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    local focused_window_json=""
    focused_window_json="$(query_focused_window_json)"
    if [ -n "$focused_window_json" ]; then
      app_name="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '.app // empty' 2>/dev/null || true)"
      if [ -n "$app_name" ]; then
        printf '%s' "$app_name"
      fi
    fi
  fi
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
    if printf '%s\n' "$focused_window_json" | "$JQ_BIN" -e --arg app "$app_name" '((.app // "") | ascii_downcase) == ($app | ascii_downcase) and (."is-minimized" // false) == false' >/dev/null 2>&1; then
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
      map(select(((.app // "") | ascii_downcase) == ($app | ascii_downcase) and (."is-minimized" // false) == false))
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

write_front_app_cache() {
  local app_name current_space_json current_space_index current_display_index current_space_visible
  local window_json window_space window_display window_focused window_space_type floating sticky fullscreen layer state_icon state_label location_label

  app_name="$(resolve_front_app_name)"
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

  state_icon="󰋽"
  state_label="No managed window"
  location_label="Space ${current_space_index:-?} · Display ${current_display_index:-?}"
  window_json=""

  if [ -n "$app_name" ] && [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    window_json="$(select_matching_window_json "$app_name" "${current_space_index:-0}" "${current_display_index:-0}")"
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

    floating="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."is-floating" // false' 2>/dev/null || echo false)"
    sticky="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."is-sticky" // false' 2>/dev/null || echo false)"
    fullscreen="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."has-fullscreen-zoom" // ."is-native-fullscreen" // false' 2>/dev/null || echo false)"
    layer="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.layer // "normal"' 2>/dev/null || echo normal)"

    if [ "$fullscreen" = "true" ]; then
      state_icon="󰊓"
      state_label="Fullscreen"
    elif [ "$floating" = "true" ]; then
      state_icon="󰒄"
      state_label="Floating"
    else
      state_icon="󰆾"
      state_label="Tiled"
    fi

    if [ "$sticky" = "true" ]; then
      state_label="$state_label · Sticky"
    fi

    case "$layer" in
      above) state_label="$state_label · Above" ;;
      below) state_label="$state_label · Below" ;;
    esac

    state_label="$(append_space_context_label "$state_label" "$floating" "$window_space_type")"
    location_label="Space ${window_space:-${current_space_index:-?}} · Display ${window_display:-${current_display_index:-?}}"
  fi

  {
    emit_line app_name "$app_name"
    emit_line state_icon "$state_icon"
    emit_line state_label "$state_label"
    emit_line location_label "$location_label"
    emit_line space_index "${current_space_index:-}"
    emit_line display_index "${current_display_index:-}"
    emit_line space_visible "${current_space_visible:-false}"
  } | write_atomic "$FRONT_APP_FILE"
}

player_is_running() {
  local player="$1"
  [ "$(osascript_safe -e "application \"$player\" is running")" = "true" ]
}

player_state() {
  local player="$1"
  osascript_safe -e "tell application \"$player\" to return (player state as string)"
}

player_track() {
  local player="$1"
  osascript_safe -e "tell application \"$player\" to return (name of current track as string)"
}

player_artist() {
  local player="$1"
  osascript_safe -e "tell application \"$player\" to return (artist of current track as string)"
}

resolve_player() {
  local candidate state fallback=""
  for candidate in Spotify Music; do
    if player_is_running "$candidate"; then
      state="$(player_state "$candidate")"
      if [ "$state" = "playing" ]; then
        printf '%s' "$candidate"
        return 0
      fi
      if [ -z "$fallback" ]; then
        fallback="$candidate"
      fi
    fi
  done
  printf '%s' "$fallback"
}

write_media_cache() {
  local player state track artist toggle_label toggle_icon current_output

  player="$(resolve_player)"
  state="stopped"
  track=""
  artist=""
  toggle_label="Play"
  toggle_icon="󰐊"

  if [ -n "$player" ]; then
    state="$(player_state "$player")"
    track="$(player_track "$player")"
    artist="$(player_artist "$player")"
    if [ "$state" = "playing" ]; then
      toggle_label="Pause"
      toggle_icon="󰏤"
    fi
  fi

  current_output="$(current_output_name)"

  {
    emit_line player "$player"
    emit_line state "$state"
    emit_line track "$track"
    emit_line artist "$artist"
    emit_line toggle_label "$toggle_label"
    emit_line toggle_icon "$toggle_icon"
    emit_line current_output "$current_output"
  } | write_atomic "$MEDIA_FILE"
}

write_outputs_cache() {
  local current_output output_name index=1
  current_output="$(current_output_name)"

  {
    if [ -n "$SWITCH_AUDIO_SOURCE_BIN" ]; then
      while IFS= read -r output_name; do
        [ -n "$output_name" ] || continue
        if [ "$output_name" = "$current_output" ]; then
          printf 'output\t%s\ttrue\t%s\n' "$index" "$output_name"
        else
          printf 'output\t%s\tfalse\t%s\n' "$index" "$output_name"
        fi
        index=$((index + 1))
      done < <($SWITCH_AUDIO_SOURCE_BIN -a -t output 2>/dev/null || true)
    fi
  } | write_atomic "$OUTPUTS_FILE"
}

refresh_all() {
  refresh_front_app_cache
  write_media_cache
  write_outputs_cache
}

ensure_cache() {
  local target="$1"
  local section="${2:-all}"
  if [ -s "$target" ]; then
    return 0
  fi
  case "$section" in
    front-app) refresh_front_app_cache ;;
    media)
      write_media_cache
      write_outputs_cache
      ;;
    *) refresh_all ;;
  esac
}

print_cache() {
  local target="$1"
  local section="${2:-all}"
  ensure_cache "$target" "$section"
  [ -f "$target" ] || return 0
  cat "$target"
}

switch_output_by_index() {
  local target_index="${1:-}"
  local target_name=""
  [ -n "$target_index" ] || return 1
  [ -n "$SWITCH_AUDIO_SOURCE_BIN" ] || return 1

  ensure_cache "$OUTPUTS_FILE" media
  if [ -f "$OUTPUTS_FILE" ]; then
    while IFS=$'\t' read -r kind index selected name; do
      [ "$kind" = "output" ] || continue
      if [ "$index" = "$target_index" ]; then
        target_name="$name"
        break
      fi
    done < "$OUTPUTS_FILE"
  fi

  [ -n "$target_name" ] || return 1
  "$SWITCH_AUDIO_SOURCE_BIN" -s "$target_name" -t output >/dev/null 2>&1 || return 1
  write_media_cache
  write_outputs_cache
}

daemon_loop() {
  local helper_pid=""
  trap 'exit 0' INT TERM

  if runtime_context_helper_available; then
    refresh_front_app_cache >/dev/null 2>&1 || true
    BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
      BARISTA_YABAI_BIN="$YABAI_BIN" \
      BARISTA_RUNTIME_CONTEXT_INTERVAL="$INTERVAL_SECONDS" \
      "$RUNTIME_CONTEXT_HELPER_BIN" daemon >/dev/null 2>&1 &
    helper_pid=$!
    trap '
      if [ -n "$helper_pid" ]; then
        kill "$helper_pid" >/dev/null 2>&1 || true
        wait "$helper_pid" >/dev/null 2>&1 || true
      fi
      exit 0
    ' INT TERM
  fi

  while true; do
    if [ -n "$helper_pid" ]; then
      if ! kill -0 "$helper_pid" >/dev/null 2>&1; then
        helper_pid=""
      fi
    fi

    if [ -n "$helper_pid" ]; then
      write_media_cache >/dev/null 2>&1 || true
      write_outputs_cache >/dev/null 2>&1 || true
    else
      refresh_all >/dev/null 2>&1 || true
    fi
    sleep "$INTERVAL_SECONDS"
  done
}

COMMAND="${1:-}"
case "$COMMAND" in
  refresh)
    case "${2:-all}" in
      front-app) write_front_app_cache ;;
      media) write_media_cache; write_outputs_cache ;;
      all|"") refresh_all ;;
      *) usage; exit 1 ;;
    esac
    ;;
  daemon)
    daemon_loop
    ;;
  front-app)
    if runtime_context_helper_available; then
      normalize_front_app_output "$(run_runtime_context_helper "$COMMAND")"
    else
      print_cache "$FRONT_APP_FILE" front-app
    fi
    ;;
  focused-space)
    if runtime_context_helper_available; then
      normalize_front_app_output "$(run_runtime_context_helper "$COMMAND")"
    else
      write_front_app_cache
      cat "$FRONT_APP_FILE"
    fi
    ;;
  media-status)
    print_cache "$MEDIA_FILE" media
    ;;
  outputs)
    print_cache "$OUTPUTS_FILE" media
    ;;
  switch-output)
    switch_output_by_index "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
