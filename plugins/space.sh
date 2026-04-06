#!/bin/sh

# Lightweight per-space script.
# Active/idle visuals are now updated in batch by space_visuals.sh.

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
CONFIG_DIR="${CONFIG_DIR:-${HOME}/.config/sketchybar}"
HOVER_STATE_DIR="${BARISTA_SPACE_HOVER_STATE_DIR:-$CONFIG_DIR/cache/space_hover}"

HOVER_BG="0x60cba6f7"
IDLE_ICON_COLOR="0xFFa6adc8"

state_file() {
  local key="${NAME:-space}"
  key="$(printf '%s' "$key" | tr -cs '[:alnum:]._-' '_')"
  printf '%s/%s.state' "$HOVER_STATE_DIR" "$key"
}

cache_current_style() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  [ -n "$JQ_BIN" ] || return 1
  [ -n "${NAME:-}" ] || return 1

  local current_style cache_file
  cache_file="$(state_file)"
  mkdir -p "$HOVER_STATE_DIR" 2>/dev/null || true
  current_style="$("$SKETCHYBAR_BIN" --query "$NAME" 2>/dev/null | "$JQ_BIN" -r '[.geometry.background.drawing, .geometry.background.color, .icon.color] | @tsv' 2>/dev/null || true)"
  [ -n "$current_style" ] || return 1
  printf '%s\n' "$current_style" > "$cache_file" 2>/dev/null || true
}

restore_cached_style() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  [ -n "${NAME:-}" ] || return 1

  local cache_file background_drawing background_color icon_color
  cache_file="$(state_file)"
  [ -f "$cache_file" ] || return 1

  IFS=$'\t' read -r background_drawing background_color icon_color < "$cache_file" || return 1
  rm -f "$cache_file" >/dev/null 2>&1 || true
  [ -n "$background_drawing" ] || return 1
  [ -n "$background_color" ] || return 1
  [ -n "$icon_color" ] || return 1

  "$SKETCHYBAR_BIN" --set "$NAME" \
    background.drawing="$background_drawing" \
    background.color="$background_color" \
    icon.color="$icon_color"
}

restore_visual_state() {
  if restore_cached_style; then
    return 0
  fi

  [ -n "$SKETCHYBAR_BIN" ] || return 0
  "$SKETCHYBAR_BIN" --trigger space_visual_refresh >/dev/null 2>&1 || true
}

case "${SENDER:-}" in
  mouse.entered)
    cache_current_style || true
    "$SKETCHYBAR_BIN" --set "$NAME" \
      background.drawing=on \
      background.color="$HOVER_BG" \
      icon.color="$IDLE_ICON_COLOR"
    ;;
  mouse.exited)
    restore_visual_state
    ;;
esac
