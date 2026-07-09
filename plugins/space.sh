#!/bin/sh

# Lightweight per-space script.
# Active/idle visuals are now updated in batch by space_visuals.sh.

PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

# common.sh resolves the real binary before defining the sketchybar() wrapper.
# Do not run `command -v sketchybar` here: after common.sh is sourced it can
# resolve to the wrapper function name and recurse under SketchyBar.
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
CONFIG_DIR="${CONFIG_DIR:-${HOME}/.config/sketchybar}"
SPACE_VISUALS_STATE_DIR="${BARISTA_SPACE_VISUALS_STATE_DIR:-$CONFIG_DIR/cache/space_visuals}"

[ -r "${_d}/lib/space_style.sh" ] && . "${_d}/lib/space_style.sh"

restore_visual_state() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  [ -n "${NAME:-}" ] || return 1

  set -- "$NAME"
  if space_style_saved_props "$NAME" >/dev/null 2>&1; then
    while IFS= read -r prop; do
      [ -n "$prop" ] && set -- "$@" "$prop"
    done <<EOF
$(space_style_saved_props "$NAME")
EOF
  else
    while IFS= read -r prop; do
      [ -n "$prop" ] && set -- "$@" "$prop"
    done <<EOF
$(space_style_props idle)
EOF
  fi

  "$SKETCHYBAR_BIN" --set "$@"
}

apply_hover_state() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  [ -n "${NAME:-}" ] || return 1

  style_state="$(space_style_saved_state "$NAME" 2>/dev/null || true)"
  if [ "$style_state" = "focused" ]; then
    hover_state="focused"
  else
    hover_state="hover"
  fi

  set -- "$NAME"
  while IFS= read -r prop; do
    [ -n "$prop" ] && set -- "$@" "$prop"
  done <<EOF
$(space_style_props "$hover_state")
EOF
  "$SKETCHYBAR_BIN" --set "$@"
}

case "${SENDER:-}" in
  mouse.entered)
    state_path="$(hover_state_file "$NAME")"
    token="$(hover_token)"
    printf '%s' "$token" > "$state_path"
    apply_hover_state
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
