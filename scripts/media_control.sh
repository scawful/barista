#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

COMMAND="${1:-status}"
PLAYER_OVERRIDE="${2:-}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"
SWITCH_AUDIO_SOURCE_BIN="${BARISTA_SWITCH_AUDIO_SOURCE_BIN:-$(command -v SwitchAudioSource 2>/dev/null || true)}"
_d="${0%/*}"
[ -z "$_d" ] && _d="."
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-${_d}/runtime_context.sh}"

emit() {
  printf '%s\t%s\n' "$1" "$2"
}

osascript_safe() {
  [ -n "$OSASCRIPT_BIN" ] || return 0
  "$OSASCRIPT_BIN" "$@" 2>/dev/null || true
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
  if [ -n "$PLAYER_OVERRIDE" ]; then
    printf '%s' "$PLAYER_OVERRIDE"
    return 0
  fi

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

runtime_context_status() {
  [ -x "$RUNTIME_CONTEXT_SCRIPT" ] || return 1
  "$RUNTIME_CONTEXT_SCRIPT" media-status 2>/dev/null || true
}

runtime_context_outputs() {
  [ -x "$RUNTIME_CONTEXT_SCRIPT" ] || return 1
  "$RUNTIME_CONTEXT_SCRIPT" outputs 2>/dev/null || true
}

refresh_runtime_context_media() {
  [ -x "$RUNTIME_CONTEXT_SCRIPT" ] || return 0
  "$RUNTIME_CONTEXT_SCRIPT" refresh media >/dev/null 2>&1 || true
}

print_status() {
  local player state track artist toggle_label toggle_icon output current_output
  local runtime_output

  runtime_output="$(runtime_context_status || true)"
  if [ -n "$runtime_output" ]; then
    printf '%s\n' "$runtime_output"
    exit 0
  fi

  player="$(resolve_player)"

  if [ -z "$player" ]; then
    emit player ""
    emit state "stopped"
    emit track ""
    emit artist ""
    emit toggle_label "Play"
    emit toggle_icon "󰐊"
    exit 0
  fi

  state="$(player_state "$player")"
  track="$(player_track "$player")"
  artist="$(player_artist "$player")"

  if [ "$state" = "playing" ]; then
    toggle_label="Pause"
    toggle_icon="󰏤"
  else
    toggle_label="Play"
    toggle_icon="󰐊"
  fi

  emit player "$player"
  emit state "${state:-stopped}"
  emit track "${track:-}"
  emit artist "${artist:-}"
  emit toggle_label "$toggle_label"
  emit toggle_icon "$toggle_icon"

  current_output=""
  if [ -n "$SWITCH_AUDIO_SOURCE_BIN" ]; then
    current_output="$($SWITCH_AUDIO_SOURCE_BIN -c -t output 2>/dev/null || true)"
  fi
  emit current_output "$current_output"
}

print_outputs() {
  local runtime_output current_output output_name index

  runtime_output="$(runtime_context_outputs || true)"
  if [ -n "$runtime_output" ]; then
    printf '%s\n' "$runtime_output"
    exit 0
  fi

  [ -n "$SWITCH_AUDIO_SOURCE_BIN" ] || exit 0
  current_output="$($SWITCH_AUDIO_SOURCE_BIN -c -t output 2>/dev/null || true)"
  index=1
  while IFS= read -r output_name; do
    [ -n "$output_name" ] || continue
    if [ "$output_name" = "$current_output" ]; then
      printf 'output\t%s\ttrue\t%s\n' "$index" "$output_name"
    else
      printf 'output\t%s\tfalse\t%s\n' "$index" "$output_name"
    fi
    index=$((index + 1))
  done < <($SWITCH_AUDIO_SOURCE_BIN -a -t output 2>/dev/null || true)
}

dispatch_command() {
  local player="$1"
  local command="$2"
  [ -n "$player" ] || exit 0

  case "$command" in
    playpause)
      osascript_safe -e "tell application \"$player\" to playpause" >/dev/null
      ;;
    next)
      osascript_safe -e "tell application \"$player\" to next track" >/dev/null
      ;;
    previous)
      osascript_safe -e "tell application \"$player\" to previous track" >/dev/null
      ;;
  esac

  refresh_runtime_context_media
}

switch_output() {
  local output_index="${1:-}"

  [ -n "$output_index" ] || exit 1
  if [ -x "$RUNTIME_CONTEXT_SCRIPT" ]; then
    "$RUNTIME_CONTEXT_SCRIPT" switch-output "$output_index" >/dev/null 2>&1 && exit 0
  fi
  [ -n "$SWITCH_AUDIO_SOURCE_BIN" ] || exit 1

  local target_name=""
  while IFS=$'\t' read -r kind index selected name; do
    [ "$kind" = "output" ] || continue
    if [ "$index" = "$output_index" ]; then
      target_name="$name"
      break
    fi
  done < <(print_outputs)

  [ -n "$target_name" ] || exit 1
  "$SWITCH_AUDIO_SOURCE_BIN" -s "$target_name" -t output >/dev/null
  refresh_runtime_context_media
}

case "$COMMAND" in
  status)
    print_status
    ;;
  outputs)
    print_outputs
    ;;
  set-output)
    switch_output "$PLAYER_OVERRIDE"
    ;;
  playpause|next|previous)
    dispatch_command "$(resolve_player)" "$COMMAND"
    ;;
  *)
    echo "Usage: $0 [status|outputs|set-output <index>|playpause|next|previous] [player]" >&2
    exit 1
    ;;
esac
