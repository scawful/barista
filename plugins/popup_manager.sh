#!/bin/bash
# Thin fallback stub — the compiled C binary (popup_manager) handles this.
# This script exists only as a fallback for Lua-only mode.

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

TMPDIR="${TMPDIR:-/tmp}"
POPUP_ITEMS=()
SUBMENU_ITEMS=()

load_items() {
  local path="$1"
  local target="$2"
  if [ -f "$path" ]; then
    mapfile -t "$target" < "$path"
    return 0
  fi
  return 1
}

if ! load_items "$TMPDIR/sketchybar_popup_list" POPUP_ITEMS; then
  POPUP_ITEMS=(apple_menu front_app clock system_info volume battery control_center)
fi

if ! load_items "$TMPDIR/sketchybar_submenu_list" SUBMENU_ITEMS; then
  SUBMENU_ITEMS=(yaze.recent_roms emacs.recent_org)
fi

dismiss_all() {
  local args=()
  for item in "${POPUP_ITEMS[@]}"; do
    [ -n "$item" ] || continue
    args+=(--set "$item" popup.drawing=off)
  done
  for item in "${SUBMENU_ITEMS[@]}"; do
    [ -n "$item" ] || continue
    args+=(--set "$item" popup.drawing=off background.drawing=off background.color=0x00000000)
  done
  sketchybar "${args[@]}" >/dev/null 2>&1 || true
}

case "${SENDER:-}" in
  "space_change"|"display_changed"|"display_added"|"display_removed"|"system_woke"|"front_app_switched")
    dismiss_all
    ;;
esac
