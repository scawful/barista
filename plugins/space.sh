#!/bin/sh

# Lightweight per-space script.
# Active/idle visuals are now updated in batch by space_visuals.sh.

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
CONFIG_DIR="${CONFIG_DIR:-${HOME}/.config/sketchybar}"
SPACE_VISUALS_STATE_DIR="${BARISTA_SPACE_VISUALS_STATE_DIR:-$CONFIG_DIR/cache/space_visuals}"
LAST_SELECTED_SPACE_FILE="$SPACE_VISUALS_STATE_DIR/last_selected_space"

HOVER_BG="0x60cba6f7"
IDLE_BG="0x00000000"
IDLE_ICON_COLOR="0xFFa6adc8"
SELECTED_BG="0xFFcba6f7"
SELECTED_ICON_COLOR="0xFF11111b"

space_index() {
  case "${NAME:-}" in
    space.[0-9]*)
      printf '%s' "${NAME#space.}"
      ;;
  esac
}

restore_visual_state() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  [ -n "${NAME:-}" ] || return 1

  local current_index last_selected_space
  current_index="$(space_index)"
  [ -n "$current_index" ] || return 1

  last_selected_space=""
  if [ -f "$LAST_SELECTED_SPACE_FILE" ]; then
    IFS= read -r last_selected_space < "$LAST_SELECTED_SPACE_FILE" || true
  fi

  if [ -n "$last_selected_space" ] && [ "$last_selected_space" = "$current_index" ]; then
    "$SKETCHYBAR_BIN" --set "$NAME" \
      background.drawing=on \
      background.color="$SELECTED_BG" \
      icon.color="$SELECTED_ICON_COLOR"
    return 0
  fi

  "$SKETCHYBAR_BIN" --set "$NAME" \
    background.drawing=off \
    background.color="$IDLE_BG" \
    icon.color="$IDLE_ICON_COLOR"
}

case "${SENDER:-}" in
  mouse.entered)
    state_path="$(hover_state_file "$NAME")"
    token="$(hover_token)"
    printf '%s' "$token" > "$state_path"
    "$SKETCHYBAR_BIN" --set "$NAME" \
      background.drawing=on \
      background.color="$HOVER_BG" \
      icon.color="$IDLE_ICON_COLOR"
    case "$HOVER_TIMEOUT" in
      ""|0|0.0|false|off)
        ;;
      *)
        (
          sleep "$HOVER_TIMEOUT"
          current=""
          if [ -f "$state_path" ]; then
            IFS= read -r current < "$state_path" || true
          fi
          if [ "$current" = "$token" ]; then
            NAME="$NAME" SKETCHYBAR_BIN="$SKETCHYBAR_BIN" LAST_SELECTED_SPACE_FILE="$LAST_SELECTED_SPACE_FILE" \
              IDLE_BG="$IDLE_BG" IDLE_ICON_COLOR="$IDLE_ICON_COLOR" \
              SELECTED_BG="$SELECTED_BG" SELECTED_ICON_COLOR="$SELECTED_ICON_COLOR" \
              restore_visual_state
          fi
        ) >/dev/null 2>&1 &
        ;;
    esac
    ;;
  mouse.exited)
    rm -f "$(hover_state_file "$NAME")" >/dev/null 2>&1 || true
    restore_visual_state
    ;;
esac
