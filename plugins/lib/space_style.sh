# Shared visual constants and state helpers for Barista space chips.
#
# Sourced by space_visuals.sh (authoritative style writer) and space.sh
# (hover/restore only). Values intentionally include the full property set so a
# hovered item can return to focused/visible/idle state without guessing.

# Also simple_spaces.sh's default, for the chips it creates.
SPACE_ICON_FONT="${SPACE_ICON_FONT:-Hack Nerd Font:Bold:16.0}"

SPACE_FOCUSED_BG="${SPACE_FOCUSED_BG:-0xffd8c4ff}"
SPACE_FOCUSED_BORDER_WIDTH="${SPACE_FOCUSED_BORDER_WIDTH:-0}"
SPACE_FOCUSED_BORDER_COLOR="${SPACE_FOCUSED_BORDER_COLOR:-0xffffffff}"
SPACE_FOCUSED_ICON_COLOR="${SPACE_FOCUSED_ICON_COLOR:-0xff11111b}"

# Chips are flat: fill alone marks focused and visible spaces.
SPACE_VISIBLE_BG="${SPACE_VISIBLE_BG:-0x40d8c4ff}"
SPACE_VISIBLE_BORDER_WIDTH="${SPACE_VISIBLE_BORDER_WIDTH:-0}"
SPACE_VISIBLE_BORDER_COLOR="${SPACE_VISIBLE_BORDER_COLOR:-0x66d8c4ff}"
SPACE_VISIBLE_ICON_COLOR="${SPACE_VISIBLE_ICON_COLOR:-0xffcdd6f4}"

SPACE_IDLE_BG="${SPACE_IDLE_BG:-0x18313a46}"
SPACE_IDLE_BORDER_WIDTH="${SPACE_IDLE_BORDER_WIDTH:-0}"
SPACE_IDLE_BORDER_COLOR="${SPACE_IDLE_BORDER_COLOR:-0x00000000}"
SPACE_IDLE_ICON_COLOR="${SPACE_IDLE_ICON_COLOR:-0xffbac2de}"

SPACE_HOVER_BG="${SPACE_HOVER_BG:-0x50d8c4ff}"
SPACE_HOVER_BORDER_WIDTH="${SPACE_HOVER_BORDER_WIDTH:-0}"
SPACE_HOVER_BORDER_COLOR="${SPACE_HOVER_BORDER_COLOR:-0x99d8c4ff}"
SPACE_HOVER_ICON_COLOR="${SPACE_HOVER_ICON_COLOR:-0xffffffff}"

# With native hover (the Barista SketchyBar fork; common.sh reads the marker
# main.lua writes) each state carries its own hover fill instead of space.sh
# swapping in the hover state. The focused chip keeps its look: alpha 0 means
# "use the idle color".
space_style_hover_props() {
  [ "${BARISTA_NATIVE_HOVER:-0}" = "1" ] || return 0
  case "${1:-idle}" in
    focused)
      printf '%s\n' "background.hover_color=0x00000000" "background.hover_border_color=0x00000000"
      ;;
    hover) ;;
    *)
      printf '%s\n' "background.hover_color=$SPACE_HOVER_BG" "background.hover_border_color=$SPACE_HOVER_BORDER_COLOR"
      ;;
  esac
}

space_style_state_root() {
  printf '%s/style_state' "${SPACE_VISUALS_STATE_DIR:?}"
}

space_style_key() {
  printf '%s' "${1:-space}" | tr -cs '[:alnum:]._-' '_'
}

space_style_state_file() {
  printf '%s/%s.state' "$(space_style_state_root)" "$(space_style_key "$1")"
}

space_style_props() {
  case "${1:-idle}" in
    focused)
      printf '%s\n' \
        "icon.font=$SPACE_ICON_FONT" \
        "label.drawing=off" \
        "background.drawing=on" \
        "background.color=$SPACE_FOCUSED_BG" \
        "background.border_width=$SPACE_FOCUSED_BORDER_WIDTH" \
        "background.border_color=$SPACE_FOCUSED_BORDER_COLOR" \
        "icon.color=$SPACE_FOCUSED_ICON_COLOR"
      ;;
    visible)
      printf '%s\n' \
        "icon.font=$SPACE_ICON_FONT" \
        "label.drawing=off" \
        "background.drawing=on" \
        "background.color=$SPACE_VISIBLE_BG" \
        "background.border_width=$SPACE_VISIBLE_BORDER_WIDTH" \
        "background.border_color=$SPACE_VISIBLE_BORDER_COLOR" \
        "icon.color=$SPACE_VISIBLE_ICON_COLOR"
      ;;
    hover)
      printf '%s\n' \
        "icon.font=$SPACE_ICON_FONT" \
        "label.drawing=off" \
        "background.drawing=on" \
        "background.color=$SPACE_HOVER_BG" \
        "background.border_width=$SPACE_HOVER_BORDER_WIDTH" \
        "background.border_color=$SPACE_HOVER_BORDER_COLOR" \
        "icon.color=$SPACE_HOVER_ICON_COLOR"
      ;;
    idle|*)
      printf '%s\n' \
        "icon.font=$SPACE_ICON_FONT" \
        "label.drawing=off" \
        "background.drawing=on" \
        "background.color=$SPACE_IDLE_BG" \
        "background.border_width=$SPACE_IDLE_BORDER_WIDTH" \
        "background.border_color=$SPACE_IDLE_BORDER_COLOR" \
        "icon.color=$SPACE_IDLE_ICON_COLOR"
      ;;
  esac
  space_style_hover_props "${1:-idle}"
}

space_style_remember() {
  item="${1:-}"
  state="${2:-idle}"
  [ -n "$item" ] || return 0
  dir="$(space_style_state_root)"
  mkdir -p "$dir" 2>/dev/null || true
  {
    printf 'state=%s\n' "$state"
    space_style_props "$state"
  } > "$(space_style_state_file "$item")" 2>/dev/null || true
}

space_style_saved_state() {
  file="$(space_style_state_file "$1")"
  [ -f "$file" ] || return 1
  IFS= read -r first_line < "$file" || return 1
  case "$first_line" in
    state=*) printf '%s' "${first_line#state=}" ;;
    *) return 1 ;;
  esac
}

space_style_saved_props() {
  file="$(space_style_state_file "$1")"
  [ -f "$file" ] || return 1
  tail -n +2 "$file"
}
