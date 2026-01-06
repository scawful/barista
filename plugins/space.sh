#!/bin/sh

# Modern Yabai Space Indicator - Icon-only with app persistence
# OPTIMIZED: Replaced Python calls with jq for better performance

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
YABAI_BIN="$(command -v yabai 2>/dev/null || true)"
SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-}"

expand_path() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

if [ -z "$SCRIPTS_DIR" ] && [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
  SCRIPTS_DIR=$(jq -r '.paths.scripts_dir // .paths.scripts // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ "$SCRIPTS_DIR" = "null" ]; then
    SCRIPTS_DIR=""
  fi
fi

if [ -n "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$(expand_path "$SCRIPTS_DIR")"
fi

if [ -z "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$CONFIG_DIR/scripts"
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$HOME/.config/scripts"
fi

ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh"
SPACE_INDEX="${NAME#space.}"
ICON_CACHE_DIR="$HOME/.config/sketchybar/cache/space_icons"
ICON_CACHE_FILE="$ICON_CACHE_DIR/$SPACE_INDEX"
SELECTED_STATE="${SELECTED:-}"

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

# OPTIMIZED: Cache yabai space data to avoid redundant queries
SPACE_DATA_CACHE=""
get_space_data() {
  if [ -n "$SPACE_DATA_CACHE" ]; then
    printf '%s' "$SPACE_DATA_CACHE"
    return 0
  fi
  [ -n "$YABAI_BIN" ] || return 1
  SPACE_DATA_CACHE=$("$YABAI_BIN" -m query --spaces --space "$SPACE_INDEX" 2>/dev/null) || return 1
  printf '%s' "$SPACE_DATA_CACHE"
}

resolve_selected_state() {
  if [ -n "$SELECTED_STATE" ]; then
    return 0
  fi
  [ -n "$JQ_BIN" ] || return 0
  local data
  data=$(get_space_data) || return 0
  local focused
  focused=$(printf '%s' "$data" | "$JQ_BIN" -r '."has-focus" // empty')
  if [ -n "$focused" ]; then
    SELECTED_STATE="$focused"
  fi
}

read_cached_icon() {
  [ -f "$ICON_CACHE_FILE" ] || return 0
  cat "$ICON_CACHE_FILE" 2>/dev/null || true
}

write_cached_icon() {
  mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || true
  printf '%s' "$1" > "$ICON_CACHE_FILE" 2>/dev/null || true
}

should_refresh_app_icon() {
  case "$SENDER" in
    space_change|space_mode_refresh|front_app_switched)
      resolve_selected_state
      is_selected "$SELECTED_STATE" && return 0
      ;;
  esac
  return 1
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

# OPTIMIZED: Use cached space data, single layout command
ensure_space_layout() {
  [ -n "$YABAI_BIN" ] || return
  [ -n "$JQ_BIN" ] || return
  local desired="$(get_space_mode)"
  if [ -z "$desired" ]; then
    return
  fi
  local info
  info=$(get_space_data) || return  # Use cached data
  local current_type
  current_type=$(printf '%s' "$info" | "$JQ_BIN" -r '.type // "unknown"')
  # Only change if different (single command, not two)
  if [ "$current_type" != "$desired" ]; then
    "$YABAI_BIN" -m space "$SPACE_INDEX" --layout "$desired" >/dev/null 2>&1 || true
  fi
}

# Icon selection logic - priority: custom icon > app icon > empty
# We ALWAYS try to show the app icon for all spaces (persistence)
if [ "$SENDER" = "space_mode_refresh" ]; then
  resolve_selected_state
  ensure_space_layout
elif [ "$SENDER" = "space_change" ]; then
  resolve_selected_state
  if is_selected "$SELECTED_STATE"; then
    ensure_space_layout
  fi
fi

if [ "$SENDER" != "mouse.entered" ] && [ "$SENDER" != "mouse.exited" ]; then
  ICON_VALUE=""

  # Get custom icon from state
  DEFAULT_ICON=$(get_default_icon)
  CACHED_ICON=$(read_cached_icon)

  # Priority: custom icon first
  if [ -n "$DEFAULT_ICON" ]; then
    ICON_VALUE="$DEFAULT_ICON"
  else
    if should_refresh_app_icon; then
      # Refresh app icon only for the active space to avoid startup spikes.
      APP_ICON=$(resolve_app_icon)
      if [ -n "$APP_ICON" ]; then
        ICON_VALUE="$APP_ICON"
        write_cached_icon "$APP_ICON"
      elif [ -n "$CACHED_ICON" ]; then
        ICON_VALUE="$CACHED_ICON"
      else
        # If no app, show a subtle dot for active spaces, empty icon for inactive
        if is_selected "$SELECTED_STATE"; then
          ICON_VALUE="•"
        else
          ICON_VALUE="$EMPTY_ICON"
        fi
      fi
    else
      if [ -n "$CACHED_ICON" ]; then
        ICON_VALUE="$CACHED_ICON"
      else
        if is_selected "$SELECTED_STATE"; then
          ICON_VALUE="•"
        else
          ICON_VALUE="$EMPTY_ICON"
        fi
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
  resolve_selected_state
  if is_selected "$SELECTED_STATE"; then
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
resolve_selected_state
if is_selected "$SELECTED_STATE"; then
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
