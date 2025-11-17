#!/bin/bash

# Submenu Hover - One submenu at a time with visual feedback

# Hover colors - visible highlight
HOVER_BG="0x80cba6f7"  # Mauve with 50% opacity
IDLE_BG="0x00000000"   # Transparent

# List of all submenu items
SUBMENUS=(
  "menu.sketchybar.styles"
  "menu.sketchybar.tools"
  "menu.yabai.section"
  "menu.windows.section"
  "menu.rom.section"
  "menu.emacs.section"
  "menu.apps.section"
  "menu.dev.section"
  "menu.help.section"
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
  for submenu in "${SUBMENUS[@]}"; do
    if [ "$submenu" != "$current" ]; then
      sketchybar --set "$submenu" \
        popup.drawing=off \
        background.drawing=off \
        background.color="$IDLE_BG"
    fi
  done
}

schedule_close() {
  local target="$1"
  (
    sleep "$CLOSE_DELAY"
    local active="$(current_active)"
    if [ -z "$active" ] || [ "$active" != "$target" ]; then
      sketchybar --set "$target" \
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
    sketchybar --set "$NAME" \
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
    sketchybar --set "$NAME" \
      popup.drawing=off \
      background.drawing=off \
      background.color="$IDLE_BG"
    ;;
esac
