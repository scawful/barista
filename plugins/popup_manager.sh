#!/bin/bash
# Thin fallback stub — the compiled C binary (popup_manager) handles this.
# This script exists only as a fallback for Lua-only mode.

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

POPUP_ITEMS=(apple_menu front_app clock system_info yabai_status)

dismiss_all() {
  local args=()
  for item in "${POPUP_ITEMS[@]}"; do
    args+=(--set "$item" popup.drawing=off)
  done
  sketchybar "${args[@]}" >/dev/null 2>&1 || true
}

case "${SENDER:-}" in
  "space_change"|"display_changed"|"display_added"|"display_removed"|"system_woke"|"front_app_switched")
    dismiss_all
    ;;
esac
