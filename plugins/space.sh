#!/bin/sh

# Modern Yabai Space Indicator - Icon-only with app persistence
# OPTIMIZED: Replaced Python calls with jq for better performance

STATE_FILE="$HOME/.config/sketchybar/state.json"
ICON_SCRIPT="$HOME/.config/scripts/app_icon.sh"
SPACE_INDEX="${NAME#space.}"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
YABAI_BIN="$(command -v yabai 2>/dev/null || true)"

# Modern color scheme - Catppuccin Mocha
IDLE_BG="0x00000000"                    # Transparent when idle
SELECTED_BG="0xFFcba6f7"                # Mauve - vibrant for active
HOVER_BG="0x60cba6f7"                   # Mauve with transparency for hover
IDLE_ICON_COLOR="0xFFa6adc8"            # Subtext0 - subtle
SELECTED_ICON_COLOR="0xFF11111b"        # Crust - high contrast
EMPTY_ICON="○"

icon_matches_space_number() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" = "$SPACE_INDEX" ]
}

is_selected() {
  case "$1" in
    1|true|on) return 0 ;;
    *) return 1 ;;
  esac
}

# OPTIMIZED: Use jq instead of Python for JSON parsing
get_default_icon() {
  [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ] || return
  "$JQ_BIN" -r --arg idx "$SPACE_INDEX" '.space_icons[$idx] // empty' "$STATE_FILE" 2>/dev/null
}

# OPTIMIZED: Use jq instead of Python for JSON parsing
get_space_mode() {
  [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ] || return
  "$JQ_BIN" -r --arg idx "$SPACE_INDEX" '.space_modes[$idx] // empty' "$STATE_FILE" 2>/dev/null
}

get_active_app() {
  if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return
  fi
  local data
  data=$(yabai -m query --windows --space "$SPACE_INDEX" 2>/dev/null) || return
  if [ -z "$data" ]; then
    return
  fi
  # Get the focused window's app, or first non-minimized window
  printf '%s\n' "$data" | jq -r '
    map(select(."is-minimized" == false))
    | (map(select(.["has-focus"] == true))[0] // .[0])
    | .app // empty'
}

resolve_app_icon() {
  local app
  app=$(get_active_app)
  if [ -z "$app" ]; then
    return
  fi
  if [ -x "$ICON_SCRIPT" ]; then
    local glyph
    glyph=$("$ICON_SCRIPT" "$app")
    if [ -n "$glyph" ]; then
      printf '%s' "$glyph"
    fi
  fi
}

ensure_space_layout() {
  [ -n "$YABAI_BIN" ] || return
  [ -n "$JQ_BIN" ] || return
  local desired="$(get_space_mode)"
  if [ -z "$desired" ]; then
    desired="float"
  fi
  local info
  info=$("$YABAI_BIN" -m query --spaces --space "$SPACE_INDEX" 2>/dev/null) || return
  local current_type current_float
  current_type=$(printf '%s' "$info" | "$JQ_BIN" -r '.type // "unknown"')
  current_float=$(printf '%s' "$info" | "$JQ_BIN" -r '."is-floating" // false')
  if [ "$desired" = "float" ]; then
    if [ "$current_float" != "true" ]; then
      "$YABAI_BIN" -m space "$SPACE_INDEX" --layout float >/dev/null 2>&1 || true
      "$YABAI_BIN" -m space "$SPACE_INDEX" --toggle float >/dev/null 2>&1 || true
    fi
  else
    if [ "$current_type" != "$desired" ]; then
      "$YABAI_BIN" -m space "$SPACE_INDEX" --layout "$desired" >/dev/null 2>&1 || true
    fi
  fi
}

# Icon selection logic - priority: custom icon > app icon > empty
# We ALWAYS try to show the app icon for all spaces (persistence)
if [ "$SENDER" = "space_change" ] || [ "$SENDER" = "space_mode_refresh" ]; then
  ensure_space_layout
fi

if [ "$SENDER" != "mouse.entered" ] && [ "$SENDER" != "mouse.exited" ]; then
  ICON_VALUE=""

  # Get custom icon from state
  DEFAULT_ICON=$(get_default_icon)

  # Priority: custom icon first
  if [ -n "$DEFAULT_ICON" ]; then
    ICON_VALUE="$DEFAULT_ICON"
  else
    # Otherwise, show the app icon for this space
    APP_ICON=$(resolve_app_icon)
    if [ -n "$APP_ICON" ]; then
      ICON_VALUE="$APP_ICON"
    else
      # If no app, show a subtle dot for active spaces, empty icon for inactive
      if is_selected "$SELECTED"; then
        ICON_VALUE="•"
      else
        ICON_VALUE="$EMPTY_ICON"
      fi
    fi
  fi

  # Absolute fallback: never leave the icon empty
  if [ -z "$ICON_VALUE" ]; then
    ICON_VALUE="$SPACE_INDEX"
  fi

  # Always hide label - icon-only design
  sketchybar --set "$NAME" icon="$ICON_VALUE" label.drawing=off
fi

# Hover effects
if [ "$SENDER" = "mouse.entered" ]; then
  sketchybar --set "$NAME" \
    background.drawing=on \
    background.color="$HOVER_BG" \
    icon.color="$IDLE_ICON_COLOR"
  exit 0
fi

if [ "$SENDER" = "mouse.exited" ]; then
  if is_selected "$SELECTED"; then
    sketchybar --set "$NAME" \
      background.drawing=on \
      background.color="$SELECTED_BG" \
      icon.color="$SELECTED_ICON_COLOR"
  else
    sketchybar --set "$NAME" \
      background.drawing=off \
      background.color="$IDLE_BG" \
      icon.color="$IDLE_ICON_COLOR"
  fi
  exit 0
fi

# Selection state
if is_selected "$SELECTED"; then
  sketchybar --set "$NAME" \
    background.drawing=on \
    background.color="$SELECTED_BG" \
    icon.color="$SELECTED_ICON_COLOR"
else
  sketchybar --set "$NAME" \
    background.drawing=off \
    background.color="$IDLE_BG" \
    icon.color="$IDLE_ICON_COLOR"
fi
