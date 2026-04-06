#!/bin/bash

# Volume Widget Script
# Handles volume updates and hover effects

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

if [ -z "$NAME" ]; then
  NAME="volume"
fi

ICON_OVERRIDE="${BARISTA_ICON_VOLUME:-}"
OK_COLOR="${BARISTA_VOLUME_OK:-0xffa6e3a1}"
WARN_COLOR="${BARISTA_VOLUME_WARN:-0xfff9e2af}"
LOW_COLOR="${BARISTA_VOLUME_LOW:-0xfff38ba8}"
MUTE_COLOR="${BARISTA_VOLUME_MUTE:-0xff89b4fa}"
MEDIA_CONTROL_SCRIPT="${BARISTA_MEDIA_CONTROL_SCRIPT:-$SCRIPTS_DIR/media_control.sh}"
APP_ICON_SCRIPT="${BARISTA_APP_ICON_SCRIPT:-$SCRIPTS_DIR/app_icon.sh}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"
SWITCH_AUDIO_SOURCE_BIN="${BARISTA_SWITCH_AUDIO_SOURCE_BIN:-$(command -v SwitchAudioSource 2>/dev/null || true)}"

osascript_safe() {
  [ -n "$OSASCRIPT_BIN" ] || return 0
  "$OSASCRIPT_BIN" "$@" 2>/dev/null || true
}

case "$SENDER" in
  "volume_change")
    VOLUME="$INFO"
    ;;
  "mouse.entered")
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set "$NAME" popup.drawing=off
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  *)
    # Initial load or other events - get current volume
    VOLUME="$(osascript_safe -e 'output volume of (get volume settings)')"
    ;;
esac

# If VOLUME is still empty, get it from system
if [ -z "$VOLUME" ]; then
  VOLUME="$(osascript_safe -e 'output volume of (get volume settings)')"
fi

MUTED="$(osascript_safe -e 'output muted of (get volume settings)')"
[ -n "$MUTED" ] || MUTED=false

OUTPUT_DEVICE=""
if [ -n "$SWITCH_AUDIO_SOURCE_BIN" ]; then
  OUTPUT_DEVICE=$("$SWITCH_AUDIO_SOURCE_BIN" -c -t output 2>/dev/null || true)
fi

MEDIA_PLAYER=""
MEDIA_STATE="stopped"
MEDIA_TRACK=""
MEDIA_ARTIST=""
MEDIA_TOGGLE_LABEL="Play"
MEDIA_TOGGLE_ICON="󰐊"
MEDIA_CURRENT_OUTPUT="$OUTPUT_DEVICE"
declare -a OUTPUT_SWITCH_NAMES=()
declare -a OUTPUT_SWITCH_SELECTED=()
if [ -x "$MEDIA_CONTROL_SCRIPT" ]; then
  while IFS=$'\t' read -r key value; do
    case "$key" in
      player) MEDIA_PLAYER="$value" ;;
      state) MEDIA_STATE="$value" ;;
      track) MEDIA_TRACK="$value" ;;
      artist) MEDIA_ARTIST="$value" ;;
      toggle_label) MEDIA_TOGGLE_LABEL="$value" ;;
      toggle_icon) MEDIA_TOGGLE_ICON="$value" ;;
      current_output) MEDIA_CURRENT_OUTPUT="$value" ;;
    esac
  done < <("$MEDIA_CONTROL_SCRIPT" status 2>/dev/null || true)

  while IFS=$'\t' read -r kind index selected output_name; do
    [ "$kind" = "output" ] || continue
    [ -n "$index" ] || continue
    OUTPUT_SWITCH_NAMES[$index]="$output_name"
    OUTPUT_SWITCH_SELECTED[$index]="$selected"
  done < <("$MEDIA_CONTROL_SCRIPT" outputs 2>/dev/null || true)
fi

if [ -n "$MEDIA_CURRENT_OUTPUT" ]; then
  OUTPUT_DEVICE="$MEDIA_CURRENT_OUTPUT"
fi

# Set icon based on volume level
if [ "$MUTED" = "true" ] || [ "$VOLUME" -eq 0 ]; then
  ICON="󰖁"
else
  case "$VOLUME" in
    [6-9][0-9]|100) ICON="󰕾"
    ;;
    [3-5][0-9]) ICON="󰖀"
    ;;
    [1-9]|[1-2][0-9]) ICON="󰕿"
    ;;
    *) ICON="󰖁"
  esac
fi

if [ -n "$ICON_OVERRIDE" ]; then
  ICON="$ICON_OVERRIDE"
fi

LABEL="${VOLUME}%"
COLOR="$OK_COLOR"
if [ "$MUTED" = "true" ] || [ "$VOLUME" -eq 0 ]; then
  LABEL="Muted"
  COLOR="$MUTE_COLOR"
elif [ "$VOLUME" -gt 70 ]; then
  COLOR="$OK_COLOR"
elif [ "$VOLUME" -gt 30 ]; then
  COLOR="$WARN_COLOR"
else
  COLOR="$LOW_COLOR"
fi

if [ -n "$OUTPUT_DEVICE" ]; then
  sketchybar --set volume.header label="Audio · ${OUTPUT_DEVICE}"
else
  sketchybar --set volume.header label="Audio"
fi

STATE_LABEL="$LABEL"
if [ "$MUTED" != "true" ]; then
  STATE_LABEL="${VOLUME}% volume"
fi

sketchybar --set volume.state \
  icon="$ICON" \
  label="$STATE_LABEL" \
  icon.color="$COLOR" >/dev/null 2>&1 || true

sketchybar --set volume.output \
  label="${OUTPUT_DEVICE:-System Default}" \
  icon="󰓃" \
  icon.color="$OK_COLOR" >/dev/null 2>&1 || true

for idx in 1 2 3 4; do
  output_name="${OUTPUT_SWITCH_NAMES[$idx]:-}"
  if [ -n "$output_name" ]; then
    output_selected="${OUTPUT_SWITCH_SELECTED[$idx]:-false}"
    output_color="0xffcdd6f4"
    output_label="$output_name"
    if [ "$output_selected" = "true" ]; then
      output_color="$OK_COLOR"
      output_label="${output_name} · Current"
    fi
    sketchybar --set "volume.output.$idx" \
      drawing=on \
      icon="󰓃" \
      label="$output_label" \
      icon.color="$output_color" \
      label.color="$output_color" >/dev/null 2>&1 || true
  else
    sketchybar --set "volume.output.$idx" drawing=off label="" >/dev/null 2>&1 || true
  fi
done

MEDIA_ICON="󰎈"
if [ -n "$MEDIA_PLAYER" ] && [ -x "$APP_ICON_SCRIPT" ]; then
  MEDIA_ICON="$("$APP_ICON_SCRIPT" "$MEDIA_PLAYER" 2>/dev/null || echo "󰎈")"
fi

MEDIA_LABEL="Nothing playing"
if [ -n "$MEDIA_TRACK" ] && [ -n "$MEDIA_ARTIST" ]; then
  MEDIA_LABEL="${MEDIA_TRACK} — ${MEDIA_ARTIST}"
elif [ -n "$MEDIA_TRACK" ]; then
  MEDIA_LABEL="$MEDIA_TRACK"
elif [ -n "$MEDIA_PLAYER" ]; then
  MEDIA_LABEL="${MEDIA_PLAYER} · ${MEDIA_STATE}"
fi

sketchybar --set volume.media \
  icon="$MEDIA_ICON" \
  label="$MEDIA_LABEL" \
  icon.color="$OK_COLOR" >/dev/null 2>&1 || true

sketchybar --set volume.transport.toggle \
  icon="$MEDIA_TOGGLE_ICON" \
  label="$MEDIA_TOGGLE_LABEL" >/dev/null 2>&1 || true

if [ "$MUTED" = "true" ]; then
  sketchybar --set volume.mute icon="󰖁" label="Unmute" >/dev/null 2>&1 || true
else
  sketchybar --set volume.mute icon="󰕾" label="Mute" >/dev/null 2>&1 || true
fi

# Update widget
sketchybar --set "$NAME" icon="$ICON" label="$LABEL" icon.color="$COLOR" label.color="$COLOR"
