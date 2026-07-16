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
FRONT_APP_SAFETY_INTERVAL_SECONDS="${BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL:-5}"
RUNTIME_CONTEXT_HELPER_BIN="${BARISTA_RUNTIME_CONTEXT_HELPER_BIN:-$CONFIG_DIR/bin/runtime_context_helper}"
OSASCRIPT_TIMEOUT_SECONDS="${BARISTA_RUNTIME_CONTEXT_OSASCRIPT_TIMEOUT:-1}"
AUDIO_SOURCE_TIMEOUT_SECONDS="${BARISTA_RUNTIME_CONTEXT_AUDIO_SOURCE_TIMEOUT:-1}"
MEDIA_PLAYING_TICKS="${BARISTA_RUNTIME_CONTEXT_MEDIA_PLAYING_TICKS:-1}"
MEDIA_RUNNING_TICKS="${BARISTA_RUNTIME_CONTEXT_MEDIA_RUNNING_TICKS:-2}"
MEDIA_IDLE_TICKS="${BARISTA_RUNTIME_CONTEXT_MEDIA_IDLE_TICKS:-3}"
MAX_ITERATIONS="${BARISTA_RUNTIME_CONTEXT_MAX_ITERATIONS:-0}"
MEDIA_SNAPSHOT_VERSION="barista-media-v1"
OUTPUT_ROUTE_LIMIT=4

case "$MEDIA_PLAYING_TICKS" in ''|*[!0-9]*|0) MEDIA_PLAYING_TICKS=1 ;; esac
case "$MEDIA_RUNNING_TICKS" in ''|*[!0-9]*|0) MEDIA_RUNNING_TICKS=2 ;; esac
case "$MEDIA_IDLE_TICKS" in ''|*[!0-9]*|0) MEDIA_IDLE_TICKS=3 ;; esac
case "$MAX_ITERATIONS" in ''|*[!0-9]*) MAX_ITERATIONS=0 ;; esac

read -r -d '' MEDIA_SNAPSHOT_APPLESCRIPT <<'APPLESCRIPT' || true
-- BARISTA_MEDIA_SNAPSHOT_V1
on replace_text(findText, replacementText, sourceText)
  set AppleScript's text item delimiters to findText
  set sourceParts to text items of sourceText
  set AppleScript's text item delimiters to replacementText
  set cleanedText to sourceParts as text
  set AppleScript's text item delimiters to ""
  return cleanedText
end replace_text

on clean_text(sourceValue)
  set cleanedText to sourceValue as text
  set cleanedText to my replace_text(tab, " ", cleanedText)
  set cleanedText to my replace_text(return, " ", cleanedText)
  set cleanedText to my replace_text(linefeed, " ", cleanedText)
  if (count cleanedText) > 512 then set cleanedText to text 1 thru 512 of cleanedText
  return cleanedText
end clean_text

set spotifyRunning to false
set musicRunning to false
try
  set spotifyRunning to application "Spotify" is running
end try
try
  set musicRunning to application "Music" is running
end try

set spotifyState to ""
set musicState to ""
if spotifyRunning then
  try
    tell application "Spotify" to set spotifyState to player state as text
  end try
end if
if musicRunning then
  try
    tell application "Music" to set musicState to player state as text
  end try
end if

set selectedPlayer to ""
set selectedState to "stopped"
if spotifyState is "playing" then
  set selectedPlayer to "Spotify"
  set selectedState to spotifyState
else if musicState is "playing" then
  set selectedPlayer to "Music"
  set selectedState to musicState
else if spotifyRunning then
  set selectedPlayer to "Spotify"
  if spotifyState is not "" then set selectedState to spotifyState
else if musicRunning then
  set selectedPlayer to "Music"
  if musicState is not "" then set selectedState to musicState
end if

set selectedTrack to ""
set selectedArtist to ""
if selectedPlayer is "Spotify" then
  try
    tell application "Spotify" to set selectedTrack to name of current track as text
  end try
  try
    tell application "Spotify" to set selectedArtist to artist of current track as text
  end try
else if selectedPlayer is "Music" then
  try
    tell application "Music" to set selectedTrack to name of current track as text
  end try
  try
    tell application "Music" to set selectedArtist to artist of current track as text
  end try
end if

return "snapshot_version" & tab & "barista-media-v1" & linefeed & ¬
  "player" & tab & my clean_text(selectedPlayer) & linefeed & ¬
  "state" & tab & my clean_text(selectedState) & linefeed & ¬
  "track" & tab & my clean_text(selectedTrack) & linefeed & ¬
  "artist" & tab & my clean_text(selectedArtist)
APPLESCRIPT

usage() {
  cat >&2 <<'USAGE'
Usage: runtime_context.sh <command>
  refresh [front-app|media]
  daemon
  fresh-front-app
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
  [ "${BARISTA_LUA_ONLY:-0}" != "1" ] && [ -x "$RUNTIME_CONTEXT_HELPER_BIN" ]
}

run_runtime_context_helper() {
  runtime_context_helper_available || return 1
  BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
    BARISTA_YABAI_BIN="$YABAI_BIN" \
    BARISTA_RUNTIME_CONTEXT_INTERVAL="$INTERVAL_SECONDS" \
    BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL="$FRONT_APP_SAFETY_INTERVAL_SECONDS" \
    "$RUNTIME_CONTEXT_HELPER_BIN" "$@"
}

front_app_field_value() {
  local output="${1:-}"
  local field="${2:-}"
  [ -n "$field" ] || return 0
  printf '%s\n' "$output" | awk -F'\t' -v target="$field" '$1 == target { print $2; exit }'
}

lowercase_value() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

ensure_front_app_window_available() {
  local output="${1:-}"
  [ -n "$output" ] || return 0

  printf '%s\n' "$output" | awk -F'\t' -v OFS='\t' '
    $1 == "window_available" { has_window_available = 1 }
    $1 == "state_label" { state_label = $2 }
    {
      lines[NR] = $0
      keys[NR] = $1
    }
    END {
      if (state_label == "") {
        for (i = 1; i <= NR; i++) print lines[i]
      } else {
        window_available = (state_label == "No managed window") ? "false" : "true"
        for (i = 1; i <= NR; i++) {
          print lines[i]
          if (!has_window_available && !inserted && keys[i] == "app_name") {
            print "window_available", window_available
            inserted = 1
          }
        }
        if (!has_window_available && !inserted) {
          print "window_available", window_available
        }
      }
    }
  '
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
  local runtime_app_name canonical_name normalized

  [ -n "$output" ] || return 0
  runtime_app_name="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "app_name" { print $2; exit }')"
  [ -n "$runtime_app_name" ] || {
    ensure_front_app_window_available "$output"
    return 0
  }

  canonical_name="$(canonical_front_app_name "$runtime_app_name")"
  if [ -n "$canonical_name" ] && [ "$(lowercase_value "$runtime_app_name")" = "$(lowercase_value "$canonical_name")" ]; then
    normalized="$(printf '%s\n' "$output" | awk -F'\t' -v OFS='\t' -v canonical="$canonical_name" '
      $1 == "app_name" { $2 = canonical }
      { print }
    ')"
    ensure_front_app_window_available "$normalized"
    return 0
  fi

  ensure_front_app_window_available "$output"
}

normalize_front_app_cache_file() {
  [ -s "$FRONT_APP_FILE" ] || return 0
  local normalized
  normalized="$(normalize_front_app_output "$(cat "$FRONT_APP_FILE")")"
  printf '%s\n' "$normalized" | write_atomic "$FRONT_APP_FILE"
}

front_app_output_matches_focus() {
  local output="${1:-}"
  local focused_window_json focused_minimized focused_app focused_space focused_display
  local output_app output_space output_display output_state_label

  [ -n "$output" ] || return 1
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 0

  focused_window_json="$(query_focused_window_json)"
  [ -n "$focused_window_json" ] || return 0

  focused_minimized="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '."is-minimized" // false' 2>/dev/null || echo false)"
  [ "$focused_minimized" != "true" ] || return 0

  focused_app="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '.app // empty' 2>/dev/null || true)"
  focused_space="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '.space // empty' 2>/dev/null || true)"
  focused_display="$(printf '%s\n' "$focused_window_json" | "$JQ_BIN" -r '.display // empty' 2>/dev/null || true)"
  [ -n "$focused_app" ] || return 0
  [ -n "$focused_space" ] || return 0
  [ -n "$focused_display" ] || return 0

  output_app="$(front_app_field_value "$output" app_name)"
  output_space="$(front_app_field_value "$output" space_index)"
  output_display="$(front_app_field_value "$output" display_index)"
  output_state_label="$(front_app_field_value "$output" state_label)"

  [ "$output_state_label" != "No managed window" ] || return 1
  [ -n "$output_space" ] || return 1
  [ -n "$output_display" ] || return 1
  [ "$output_space" = "$focused_space" ] || return 1
  [ "$output_display" = "$focused_display" ] || return 1

  if [ -n "$output_app" ] && [ "$(lowercase_value "$output_app")" != "$(lowercase_value "$focused_app")" ]; then
    return 1
  fi

  return 0
}

helper_front_app_output() {
  local command_name="${1:-front-app}"
  local output

  runtime_context_helper_available || return 1
  output="$(normalize_front_app_output "$(run_runtime_context_helper "$command_name" 2>/dev/null || true)")"
  [ -n "$output" ] || return 1
  front_app_output_matches_focus "$output" || return 1
  printf '%s\n' "$output"
}

helper_refreshed_front_app_output() {
  local output temp_state_dir temp_file

  runtime_context_helper_available || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  temp_state_dir="$(mktemp -d "$STATE_DIR/.helper_front_app.XXXXXX")" || return 1
  temp_file="$temp_state_dir/front_app.tsv"
  if ! BARISTA_RUNTIME_CONTEXT_DIR="$temp_state_dir" \
      BARISTA_YABAI_BIN="$YABAI_BIN" \
      BARISTA_RUNTIME_CONTEXT_INTERVAL="$INTERVAL_SECONDS" \
      BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL="$FRONT_APP_SAFETY_INTERVAL_SECONDS" \
      "$RUNTIME_CONTEXT_HELPER_BIN" refresh-front-app >/dev/null 2>&1; then
    rm -rf "$temp_state_dir"
    return 1
  fi
  output="$(cat "$temp_file" 2>/dev/null || true)"
  rm -rf "$temp_state_dir"
  [ -n "$output" ] || return 1
  output="$(normalize_front_app_output "$output")"
  front_app_output_matches_focus "$output" || return 1
  printf '%s\n' "$output"
}

write_atomic() {
  local target="$1"
  local temp_file
  if [ -d "$target" ]; then
    return 1
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  temp_file="$(mktemp "$STATE_DIR/.tmp.XXXXXX")"
  cat > "$temp_file"
  mv "$temp_file" "$target"
}

publish_snapshot() {
  local target="$1"
  local snapshot="${2:-}"
  local expected="$snapshot"
  local current=""
  local read_status=0
  local compare_limit
  local LC_ALL=C

  if [ -n "$snapshot" ]; then
    expected+=$'\n'
  fi

  if [ -f "$target" ] && [ ! -L "$target" ] && [ -r "$target" ]; then
    compare_limit=$((${#expected} + 1))
    IFS= read -r -d '' -n "$compare_limit" current < "$target" || read_status=$?
    if [ "$read_status" -ne 0 ] && [ "$current" = "$expected" ]; then
      return 0
    fi
  fi

  printf '%s' "$expected" | write_atomic "$target"
}

refresh_front_app_cache() {
  local helper_output=""
  if helper_output="$(helper_refreshed_front_app_output)"; then
    printf '%s\n' "$helper_output" | write_atomic "$FRONT_APP_FILE"
    return 0
  fi
  write_front_app_cache
}

fresh_front_app_output() {
  local output=""
  if runtime_context_helper_available; then
    output="$(run_runtime_context_helper fresh-front-app 2>/dev/null || true)"
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
      return 0
    fi
  fi

  write_front_app_cache >/dev/null
  cat "$FRONT_APP_FILE"
}

media_osascript_bounded() {
  [ -n "$OSASCRIPT_BIN" ] || return 1
  run_with_timeout "$OSASCRIPT_TIMEOUT_SECONDS" "$OSASCRIPT_BIN" "$@" 2>/dev/null
}

osascript_safe() {
  [ -n "$OSASCRIPT_BIN" ] || return 0
  "$OSASCRIPT_BIN" "$@" 2>/dev/null || true
}

media_osascript_safe() {
  media_osascript_bounded "$@" || true
}

audio_source_safe() {
  [ -n "$SWITCH_AUDIO_SOURCE_BIN" ] || return 1
  run_with_timeout "$AUDIO_SOURCE_TIMEOUT_SECONDS" "$SWITCH_AUDIO_SOURCE_BIN" "$@" 2>/dev/null
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
    output_name="$(audio_source_safe -c -t output || true)"
  fi
  sanitize_tsv_field "$output_name" 256
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

window_stack_label() {
  local window_json="${1:-}"
  local sub_layer layer

  sub_layer="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '."sub-layer" // empty' 2>/dev/null || true)"
  layer="$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.layer // "normal"' 2>/dev/null || echo normal)"

  if [ "$sub_layer" = "above" ] || [ "$layer" = "above" ]; then
    printf '%s' "Above"
    return 0
  fi

  if [ "$layer" = "below" ]; then
    printf '%s' "Below"
    return 0
  fi

  printf '%s' ""
}

write_front_app_cache() {
  local app_name current_space_json current_space_index current_display_index current_space_visible
  local window_json window_space window_display window_focused window_space_type floating sticky fullscreen stack_label state_icon state_label location_label window_available

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
  window_available="false"
  window_json=""

  if [ -n "$app_name" ] && [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    window_json="$(select_matching_window_json "$app_name" "${current_space_index:-0}" "${current_display_index:-0}")"
  fi

  if [ -n "$window_json" ]; then
    window_available="true"
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
    stack_label="$(window_stack_label "$window_json")"

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

    if [ -n "$stack_label" ]; then
      state_label="$state_label · $stack_label"
    fi

    state_label="$(append_space_context_label "$state_label" "$floating" "$window_space_type")"
    location_label="Space ${window_space:-${current_space_index:-?}} · Display ${window_display:-${current_display_index:-?}}"
  fi

  {
    emit_line app_name "$app_name"
    emit_line window_available "$window_available"
    emit_line state_icon "$state_icon"
    emit_line state_label "$state_label"
    emit_line location_label "$location_label"
    emit_line space_index "${current_space_index:-}"
    emit_line display_index "${current_display_index:-}"
    emit_line space_visible "${current_space_visible:-false}"
  } | write_atomic "$FRONT_APP_FILE"
}

sanitize_tsv_field() {
  local value="${1:-}"
  local max_length="${2:-512}"
  local LC_ALL=en_US.UTF-8
  value="${value//$'\t'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  printf '%s' "${value:0:$max_length}"
}

player_is_running() {
  local player="$1"
  [ "$(media_osascript_safe -e "application \"$player\" is running")" = "true" ]
}

player_state() {
  local player="$1"
  media_osascript_safe -e "tell application \"$player\" to return (player state as string)"
}

player_track() {
  local player="$1"
  media_osascript_safe -e "tell application \"$player\" to return (name of current track as string)"
}

player_artist() {
  local player="$1"
  media_osascript_safe -e "tell application \"$player\" to return (artist of current track as string)"
}

capture_combined_media_snapshot() {
  local output line key value
  local player="" state="" track="" artist=""
  local seen_version=0 seen_player=0 seen_state=0 seen_track=0 seen_artist=0

  output="$(media_osascript_bounded -e "$MEDIA_SNAPSHOT_APPLESCRIPT")" || return 1
  [ -n "$output" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *$'\t'*) ;;
      *) return 1 ;;
    esac
    key="${line%%$'\t'*}"
    value="${line#*$'\t'}"
    case "$value" in *$'\t'*) return 1 ;; esac

    case "$key" in
      snapshot_version)
        [ "$seen_version" -eq 0 ] && [ "$value" = "$MEDIA_SNAPSHOT_VERSION" ] || return 1
        seen_version=1
        ;;
      player)
        [ "$seen_player" -eq 0 ] || return 1
        player="$value"
        seen_player=1
        ;;
      state)
        [ "$seen_state" -eq 0 ] || return 1
        state="$value"
        seen_state=1
        ;;
      track)
        [ "$seen_track" -eq 0 ] || return 1
        track="$value"
        seen_track=1
        ;;
      artist)
        [ "$seen_artist" -eq 0 ] || return 1
        artist="$value"
        seen_artist=1
        ;;
      *) return 1 ;;
    esac
  done <<< "$output"

  [ "$seen_version" -eq 1 ] && [ "$seen_player" -eq 1 ] \
    && [ "$seen_state" -eq 1 ] && [ "$seen_track" -eq 1 ] \
    && [ "$seen_artist" -eq 1 ] || return 1
  case "$player" in ''|Spotify|Music) ;; *) return 1 ;; esac
  case "$state" in stopped|paused|playing|'fast forwarding'|rewinding) ;; *) return 1 ;; esac
  if [ -z "$player" ] && [ "$state" != "stopped" ]; then
    return 1
  fi

  MEDIA_PLAYER="$(sanitize_tsv_field "$player" 32)"
  MEDIA_STATE="$(sanitize_tsv_field "$state" 32)"
  MEDIA_TRACK="$(sanitize_tsv_field "$track" 512)"
  MEDIA_ARTIST="$(sanitize_tsv_field "$artist" 512)"
}

capture_legacy_media_snapshot() {
  local candidate candidate_state
  local fallback_player="" fallback_state="stopped"

  MEDIA_PLAYER=""
  MEDIA_STATE="stopped"
  MEDIA_TRACK=""
  MEDIA_ARTIST=""

  for candidate in Spotify Music; do
    if player_is_running "$candidate"; then
      candidate_state="$(player_state "$candidate")"
      [ -n "$candidate_state" ] || candidate_state="stopped"
      if [ "$candidate_state" = "playing" ]; then
        MEDIA_PLAYER="$candidate"
        MEDIA_STATE="$candidate_state"
        break
      fi
      if [ -z "$fallback_player" ]; then
        fallback_player="$candidate"
        fallback_state="$candidate_state"
      fi
    fi
  done

  if [ -z "$MEDIA_PLAYER" ] && [ -n "$fallback_player" ]; then
    MEDIA_PLAYER="$fallback_player"
    MEDIA_STATE="$fallback_state"
  fi
  if [ -n "$MEDIA_PLAYER" ]; then
    MEDIA_TRACK="$(player_track "$MEDIA_PLAYER")"
    MEDIA_ARTIST="$(player_artist "$MEDIA_PLAYER")"
  fi

  MEDIA_PLAYER="$(sanitize_tsv_field "$MEDIA_PLAYER" 32)"
  MEDIA_STATE="$(sanitize_tsv_field "$MEDIA_STATE" 32)"
  MEDIA_TRACK="$(sanitize_tsv_field "$MEDIA_TRACK" 512)"
  MEDIA_ARTIST="$(sanitize_tsv_field "$MEDIA_ARTIST" 512)"
}

capture_media_snapshot() {
  MEDIA_PLAYER=""
  MEDIA_STATE="stopped"
  MEDIA_TRACK=""
  MEDIA_ARTIST=""
  capture_combined_media_snapshot || capture_legacy_media_snapshot
}

write_media_cache() {
  local current_output="${1-}"
  local toggle_label="Play" toggle_icon="󰐊" snapshot

  capture_media_snapshot
  if [ "$MEDIA_STATE" = "playing" ]; then
    toggle_label="Pause"
    toggle_icon="󰏤"
  fi
  if [ "$#" -eq 0 ]; then
    current_output="$(current_output_name)"
  fi
  current_output="$(sanitize_tsv_field "$current_output" 256)"

  printf -v snapshot 'player\t%s\nstate\t%s\ntrack\t%s\nartist\t%s\ntoggle_label\t%s\ntoggle_icon\t%s\ncurrent_output\t%s' \
    "$MEDIA_PLAYER" "$MEDIA_STATE" "$MEDIA_TRACK" "$MEDIA_ARTIST" \
    "$toggle_label" "$toggle_icon" "$current_output"
  publish_snapshot "$MEDIA_FILE" "$snapshot"
}

write_outputs_cache() {
  local current_output="${1-}"
  local output_name row snapshot="" index=1
  if [ "$#" -eq 0 ]; then
    current_output="$(current_output_name)"
  fi

  if [ -n "$SWITCH_AUDIO_SOURCE_BIN" ]; then
    while IFS= read -r output_name; do
      output_name="$(sanitize_tsv_field "$output_name" 256)"
      [ -n "$output_name" ] || continue
      if [ "$output_name" = "$current_output" ]; then
        printf -v row 'output\t%s\ttrue\t%s' "$index" "$output_name"
      else
        printf -v row 'output\t%s\tfalse\t%s' "$index" "$output_name"
      fi
      if [ -n "$snapshot" ]; then
        snapshot+=$'\n'
      fi
      snapshot+="$row"
      index=$((index + 1))
      [ "$index" -le "$OUTPUT_ROUTE_LIMIT" ] || break
    done < <(audio_source_safe -a -t output || true)
  fi

  publish_snapshot "$OUTPUTS_FILE" "$snapshot"
}

refresh_media_and_outputs() {
  local current_output
  current_output="$(current_output_name)"
  write_media_cache "$current_output"
  write_outputs_cache "$current_output"
}

refresh_all() {
  refresh_front_app_cache
  refresh_media_and_outputs
}

ensure_cache() {
  local target="$1"
  local section="${2:-all}"
  if [ -s "$target" ]; then
    return 0
  fi
  case "$section" in
    front-app) refresh_front_app_cache ;;
    media) write_media_cache ;;
    outputs) write_outputs_cache ;;
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

  ensure_cache "$OUTPUTS_FILE" outputs
  if [ -f "$OUTPUTS_FILE" ]; then
    while IFS=$'\t' read -r kind index _selected name; do
      [ "$kind" = "output" ] || continue
      if [ "$index" = "$target_index" ]; then
        target_name="$name"
        break
      fi
    done < "$OUTPUTS_FILE"
  fi

  [ -n "$target_name" ] || return 1
  audio_source_safe -s "$target_name" -t output >/dev/null 2>&1 || return 1
  refresh_media_and_outputs
}

daemon_loop() {
  local helper_pid=""
  local helper_output=""
  local media_countdown=0
  local media_cadence="$MEDIA_IDLE_TICKS"
  local iterations=0
  local current_output=""
  local current_output_ready=0
  trap 'exit 0' INT TERM

  if runtime_context_helper_available; then
    if helper_output="$(helper_refreshed_front_app_output)"; then
      printf '%s\n' "$helper_output" | write_atomic "$FRONT_APP_FILE"
      BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
        BARISTA_YABAI_BIN="$YABAI_BIN" \
        BARISTA_RUNTIME_CONTEXT_INTERVAL="$INTERVAL_SECONDS" \
        BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL="$FRONT_APP_SAFETY_INTERVAL_SECONDS" \
        "$RUNTIME_CONTEXT_HELPER_BIN" daemon >/dev/null 2>&1 &
      helper_pid=$!
      trap '
        if [ -n "$helper_pid" ]; then
          kill "$helper_pid" >/dev/null 2>&1 || true
          wait "$helper_pid" >/dev/null 2>&1 || true
        fi
        exit 0
      ' INT TERM
    else
      write_front_app_cache >/dev/null 2>&1 || true
    fi
  fi

  while true; do
    if [ -n "$helper_pid" ]; then
      if ! kill -0 "$helper_pid" >/dev/null 2>&1; then
        helper_pid=""
      fi
    fi

    if [ -z "$helper_pid" ]; then
      write_front_app_cache >/dev/null 2>&1 || true
    fi

    current_output=""
    current_output_ready=0
    if [ "$media_countdown" -le 0 ]; then
      current_output="$(current_output_name)"
      current_output_ready=1
      write_media_cache "$current_output" >/dev/null 2>&1 || true
      if [ "${MEDIA_STATE:-stopped}" = "playing" ]; then
        media_cadence="$MEDIA_PLAYING_TICKS"
      elif [ -n "${MEDIA_PLAYER:-}" ]; then
        media_cadence="$MEDIA_RUNNING_TICKS"
      else
        media_cadence="$MEDIA_IDLE_TICKS"
      fi
      media_countdown=$((media_cadence - 1))
    else
      media_countdown=$((media_countdown - 1))
    fi

    if [ "$current_output_ready" -eq 0 ]; then
      current_output="$(current_output_name)"
    fi
    write_outputs_cache "$current_output" >/dev/null 2>&1 || true

    iterations=$((iterations + 1))
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$iterations" -ge "$MAX_ITERATIONS" ]; then
      break
    fi
    sleep "$INTERVAL_SECONDS"
  done

  if [ -n "$helper_pid" ]; then
    kill "$helper_pid" >/dev/null 2>&1 || true
    wait "$helper_pid" >/dev/null 2>&1 || true
  fi
}

COMMAND="${1:-}"
case "$COMMAND" in
  refresh)
    case "${2:-all}" in
      front-app) refresh_front_app_cache ;;
      media) refresh_media_and_outputs ;;
      all|"") refresh_all ;;
      *) usage; exit 1 ;;
    esac
    ;;
  daemon)
    daemon_loop
    ;;
  fresh-front-app)
    fresh_front_app_output
    ;;
  front-app)
    if helper_front_app_output "$COMMAND"; then
      :
    else
      write_front_app_cache
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
    print_cache "$OUTPUTS_FILE" outputs
    ;;
  switch-output)
    switch_output_by_index "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
