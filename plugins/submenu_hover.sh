#!/bin/bash

# Submenu Hover - One submenu at a time with visual feedback

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

# Hover colors - visible highlight (HIGHLIGHT/ANIMATION_* from common.sh, from SUBMENU_* when set by main.lua)
HOVER_BG="${SUBMENU_HOVER_BG:-0x80cba6f7}"
IDLE_BG="${SUBMENU_IDLE_BG:-0x00000000}"

# List of all submenu items
# Updated to include all sections from menu.lua
SUBMENUS=(
  "menu.control_center.app"
  "menu.windows.section"
  "menu.control_center.spaces"
  "menu.control_center.layouts"
  "menu.yabai.section"
  "menu.sketchybar.styles"
  "menu.sketchybar.tools"
  "menu.rom.section"
  "menu.emacs.section"
  "menu.halext.section"
  "menu.apps.section"
  "menu.dev.section"
  "menu.help.section"
  "menu.agents.section"
  "menu.debug.section"
)

STATE_FILE="${TMPDIR:-/tmp}/sketchybar_submenu_active"
CLOSE_DELAY="${SUBMENU_CLOSE_DELAY:-0.25}"

record_active() {
  printf "%s" "$1" >"$STATE_FILE"
}

current_active() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  fi
}

clear_active() {
  : >"$STATE_FILE"
}

close_other_submenus() {
  local current="$1"
  local args=()
  
  for submenu in "${SUBMENUS[@]}"; do
    if [ "$submenu" != "$current" ]; then
      args+=(--set "$submenu" popup.drawing=off background.drawing=off background.color="$IDLE_BG")
    fi
  done

  if [ ${#args[@]} -gt 0 ]; then
    sketchybar "${args[@]}"
  fi
}

schedule_close() {
  local target="$1"
  (
    sleep "$CLOSE_DELAY"
    local active="$(current_active)"
    if [ -z "$active" ] || [ "$active" != "$target" ]; then
      animate_set "$target" \
        popup.drawing=off \
        background.drawing=off \
        background.color="$IDLE_BG"
    fi
  ) &
}

case "${SENDER:-}" in
  "mouse.entered")
    # Close all other submenus first
    close_other_submenus "$NAME"

    record_active "$NAME"

    # Open this popup with highlight
    animate_set "$NAME" \
      popup.drawing=on \
      background.drawing=on \
      background.color="$HOVER_BG" \
      background.corner_radius=6 \
      background.padding_left=4 \
      background.padding_right=4
    ;;
  "mouse.exited")
    schedule_close "$NAME"
    ;;
  "mouse.exited.global")
    # Close when mouse leaves the entire menu area
    clear_active
    animate_set "$NAME" \
      popup.drawing=off \
      background.drawing=off \
      background.color="$IDLE_BG"
    ;;
esac
