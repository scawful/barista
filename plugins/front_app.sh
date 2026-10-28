#!/bin/bash
# OPTIMIZED: Avoid expensive osascript, use yabai if available
# Updated: Show current app glyph in the bar and full name in the popup

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-front_app}"

if [ -n "${BARISTA_SKETCHYBAR_BIN:-}" ]; then
  sketchybar() {
    "$BARISTA_SKETCHYBAR_BIN" "$@"
  }
fi

APP_NAME="${BARISTA_FRONT_APP_TARGET_APP:-${INFO:-}}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
MENU_ACTION_SCRIPT="${BARISTA_WINDOW_MENU_ACTION_SCRIPT:-$SCRIPTS_DIR/window_menu_action.sh}"
STATE_FILE="${BARISTA_STATE_FILE:-$STATE_FILE}"
FRONT_APP_CONTEXT_SCRIPT="${BARISTA_FRONT_APP_CONTEXT_SCRIPT:-$SCRIPTS_DIR/front_app_context.sh}"
RUNTIME_CONTEXT_SCRIPT="${BARISTA_RUNTIME_CONTEXT_SCRIPT:-$SCRIPTS_DIR/runtime_context.sh}"
RUNTIME_CONTEXT_HELPER_BIN="${BARISTA_RUNTIME_CONTEXT_HELPER_BIN:-$CONFIG_DIR/bin/runtime_context_helper}"
APP_ICON_SCRIPT="${BARISTA_APP_ICON_SCRIPT:-$SCRIPTS_DIR/app_icon.sh}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"

FRONT_APP_IDLE_BG="${BARISTA_ANCHOR_IDLE_BG:-0x18313a46}"
FRONT_APP_ICON_COLOR="0xFFcad3f5"
FRONT_APP_IDLE_BORDER_WIDTH="${BARISTA_ANCHOR_IDLE_BORDER_WIDTH:-0}"
FRONT_APP_IDLE_BORDER_COLOR="${BARISTA_ANCHOR_IDLE_BORDER_COLOR:-0x00000000}"
FRONT_APP_ACTION_ROWS="${BARISTA_FRONT_APP_ACTION_ROWS:-1}"
case "$FRONT_APP_ACTION_ROWS" in
  0) ;;
  *) FRONT_APP_ACTION_ROWS=1 ;;
esac
FRONT_APP_IDLE_PROPS="$(anchor_idle_props) icon.color=$FRONT_APP_ICON_COLOR"
FRONT_APP_HOVER_PROPS="$(anchor_hover_props) icon.color=$FRONT_APP_ICON_COLOR"

toggle_front_app_popup() {
  if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
    sketchybar --set front_app.more popup.drawing=off --set front_app.move popup.drawing=off --set front_app.defaults popup.drawing=off --set "$NAME" popup.drawing=toggle
  else
    sketchybar --set "$NAME" popup.drawing=toggle
  fi
}

close_front_app_popup() {
  if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
    sketchybar --set front_app.more popup.drawing=off --set front_app.move popup.drawing=off --set front_app.defaults popup.drawing=off --set "$NAME" popup.drawing=off
  else
    sketchybar --set "$NAME" popup.drawing=off
  fi
}

case "${SENDER:-}" in
  mouse.clicked)
    toggle_front_app_popup
    exit 0
    ;;
  mouse.exited.global)
    close_front_app_popup
    clear_highlight "$NAME" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
  mouse.entered)
    highlight_with_timeout "$NAME" "$FRONT_APP_HOVER_PROPS" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
  mouse.exited)
    clear_highlight "$NAME" "$FRONT_APP_IDLE_PROPS"
    exit 0
    ;;
esac

if [ "${BARISTA_FRONT_APP_ACTION:-}" = "click" ]; then
  toggle_front_app_popup
  exit 0
fi

STATE_ICON="󰋽"
STATE_LABEL="No managed window"
LOCATION_LABEL="Space ? · Display ?"
APP_ICON="󰣆"
WINDOW_AVAILABLE="false"
WINDOW_ID=""
WINDOW_SPACE_TYPE=""
STACK_BADGE=""
CONTEXT_OUTPUT=""

if [ "${SENDER:-}" = "popup_refresh" ]; then
  NATIVE_REFRESH_ATTEMPTED=0
  if [ "${BARISTA_LUA_ONLY:-0}" != "1" ] && [ -x "$RUNTIME_CONTEXT_HELPER_BIN" ]; then
    NATIVE_REFRESH_ATTEMPTED=1
    CONTEXT_OUTPUT="$(BARISTA_YABAI_BIN="$YABAI_BIN" "$RUNTIME_CONTEXT_HELPER_BIN" fresh-front-app 2>/dev/null || true)"
  fi
  if [ -z "$CONTEXT_OUTPUT" ] && [ -x "$RUNTIME_CONTEXT_SCRIPT" ]; then
    if [ "$NATIVE_REFRESH_ATTEMPTED" = "1" ]; then
      CONTEXT_OUTPUT="$(BARISTA_LUA_ONLY=1 "$RUNTIME_CONTEXT_SCRIPT" fresh-front-app 2>/dev/null || true)"
    else
      CONTEXT_OUTPUT="$("$RUNTIME_CONTEXT_SCRIPT" fresh-front-app 2>/dev/null || true)"
    fi
  fi
fi

if [ -z "$CONTEXT_OUTPUT" ] && [ -x "$FRONT_APP_CONTEXT_SCRIPT" ]; then
  CONTEXT_OUTPUT="$("$FRONT_APP_CONTEXT_SCRIPT" --app "$APP_NAME" 2>/dev/null || true)"
fi

if [ -n "$CONTEXT_OUTPUT" ]; then
  while IFS=$'\t' read -r key value; do
    case "$key" in
      app_name) APP_NAME="$value" ;;
      state_icon) STATE_ICON="$value" ;;
      state_label) STATE_LABEL="$value" ;;
      location_label) LOCATION_LABEL="$value" ;;
      window_available) WINDOW_AVAILABLE="$value" ;;
      window_id) WINDOW_ID="$value" ;;
      window_space_type) WINDOW_SPACE_TYPE="$value" ;;
      stack_badge) STACK_BADGE="$value" ;;
    esac
  done <<< "$CONTEXT_OUTPUT"
fi

if [ -z "$APP_NAME" ]; then
  if [ -n "$OSASCRIPT_BIN" ]; then
    APP_NAME=$("$OSASCRIPT_BIN" -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)
  fi
fi

if [ -z "$APP_NAME" ]; then
  exit 0
fi

# Preserve the known manual-layout label from older context snapshots.
if [ -z "$WINDOW_SPACE_TYPE" ]; then
  case "$STATE_LABEL" in *"Float Space"*) WINDOW_SPACE_TYPE="float" ;; esac
fi

# Older installed helpers do not include window_id. Recover only from a fresh,
# bounded query that matches the displayed app; never bind an unrelated focus.
case "$WINDOW_ID" in
  ''|*[!0-9]*|0)
    WINDOW_ID=""
    if [ "$WINDOW_AVAILABLE" = "true" ] && [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
      LEGACY_WINDOW="$(run_with_timeout 1 "$YABAI_BIN" -m query --windows --window 2>/dev/null || true)"
      WINDOW_ID="$(printf '%s\n' "$LEGACY_WINDOW" | "$JQ_BIN" -r --arg app "$APP_NAME" '
        select(.app == $app and .["is-minimized"] != true)
        | .id | select(type == "number" and . > 0 and floor == .)
      ' 2>/dev/null || true)"
    fi
    ;;
esac
case "$WINDOW_ID" in ''|*[!0-9]*|0) WINDOW_AVAILABLE="false"; WINDOW_ID="" ;; esac

# Filter out barista's own apps - keep previous app visible
case "$APP_NAME" in
  config_menu|config_menu_v2|Barista|BaristaControlPanel|"Barista Control Panel"|help_center|icon_browser|sketchybar)
    exit 0
    ;;
esac

if [ -x "$APP_ICON_SCRIPT" ]; then
  APP_ICON="$("$APP_ICON_SCRIPT" "$APP_NAME" 2>/dev/null || true)"
fi

if [ -z "$APP_ICON" ]; then
  APP_ICON="󰣆"
fi

FLOAT_ACTION_LABEL="Float Window"
FLOAT_ACTION_COMMAND="window-toggle-float"
FULLSCREEN_ACTION_LABEL="Enter Fullscreen"
TOPMOST_ACTION_LABEL="Always on top: Off"
STICKY_ACTION_LABEL="All spaces: Off"
TILE_PRESET_LABEL="Exit Fullscreen + Match Space"
WINDOW_COLOR="0xFFcad3f5"
if [ "$WINDOW_AVAILABLE" != "true" ]; then
  FLOAT_ACTION_LABEL="No Window Available"
  FULLSCREEN_ACTION_LABEL="No Window Available"
  TOPMOST_ACTION_LABEL="No Window Available"
  STICKY_ACTION_LABEL="No Window Available"
  TILE_PRESET_LABEL="No Window Available"
  STATE_LABEL="No window available · App defaults still apply"
  WINDOW_COLOR="0xFF6e738d"
else
  case "$STATE_LABEL" in
    *Floating*)
      case "$WINDOW_SPACE_TYPE" in
        bsp|stack) FLOAT_ACTION_LABEL="Tile Window" ;;
        *) FLOAT_ACTION_LABEL="Follow Space Layout"; FLOAT_ACTION_COMMAND="window-adopt-space-mode" ;;
      esac ;;
  esac
  case "$STATE_LABEL" in *Fullscreen*) FULLSCREEN_ACTION_LABEL="Exit Fullscreen" ;; esac
  case "$STATE_LABEL" in *Above*) TOPMOST_ACTION_LABEL="Always on top: On" ;; esac
  case "$STATE_LABEL" in *Sticky*) STICKY_ACTION_LABEL="All spaces: On" ;; esac
  if [ "$WINDOW_SPACE_TYPE" = "float" ]; then
    STATE_LABEL="${STATE_LABEL/Tiled · Float Space/Free in Manual Space}"
    STATE_LABEL="${STATE_LABEL/Float Space/Manual Space}"
  fi
fi

# Every click script is one safely quoted argv invocation, bound to this snapshot.
shell_quote() {
  local replacement="'\"'\"'"
  local value="${1//\'/$replacement}"
  printf -v "$2" "'%s'" "$value"
}
# Quote the snapshot once. These shell builtins avoid a process per menu token.
shell_quote "$MENU_ACTION_SCRIPT" Q_ACTION
shell_quote "$WINDOW_ID" Q_WINDOW
shell_quote "$APP_NAME" Q_APP
shell_quote "$CONFIG_DIR" Q_CONFIG
shell_quote "$STATE_FILE" Q_STATE
shell_quote "$SCRIPTS_DIR" Q_SCRIPTS
shell_quote "$SKETCHYBAR_BIN" Q_SKETCHYBAR
shell_quote "$YABAI_BIN" Q_YABAI
ACTION_PREFIX="env BARISTA_CONFIG_DIR=$Q_CONFIG BARISTA_STATE_FILE=$Q_STATE BARISTA_SCRIPTS_DIR=$Q_SCRIPTS BARISTA_SKETCHYBAR_BIN=$Q_SKETCHYBAR BARISTA_YABAI_BIN=$Q_YABAI $Q_ACTION"
menu_action() {
  CLICK_SCRIPT="$ACTION_PREFIX '$1' '$2' $Q_WINDOW $Q_APP"
}

SAVED_MODE="unknown"
SAVED_LEVEL="unknown"
SAVED_LABEL="Saved default unavailable"
if [ -n "$JQ_BIN" ] && [ -r "$STATE_FILE" ]; then
  # One jq on the focus hot path; each field fails closed on its own.
  IFS=$'\t' read -r SAVED_MODE SAVED_LEVEL < <("$JQ_BIN" -r --arg app "$APP_NAME" '
    if type != "object" then error("invalid state") else . end
    | [
        (try (
          (.window_defaults.apps // {}) as $apps
          | (if $apps == [] then {} elif ($apps | type) == "object" then $apps
              else error("invalid apps") end) as $valid_apps
          | ($valid_apps[$app].mode // "unset") as $mode
          | if $mode == "float" or $mode == "tile" or $mode == "unset"
            then $mode else error("invalid default") end
        ) catch "unknown"),
        (try (
          (.window_levels // {}) as $levels
          | if $levels == [] then "unset"
            elif ($levels | type) == "object" then ($levels[$app].level // "unset")
            else error("invalid levels") end
        ) catch "unknown")
      ] | @tsv
  ' "$STATE_FILE" 2>/dev/null || printf 'unknown\tunknown\n')
  SAVED_MODE="${SAVED_MODE:-unknown}"
  SAVED_LEVEL="${SAVED_LEVEL:-unknown}"
fi
case "$SAVED_MODE" in
  float) SAVED_LABEL="Saved default · Float new windows" ;;
  tile) SAVED_LABEL="Saved default · Tile in managed spaces" ;;
  unset) SAVED_LABEL="Saved default · None" ;;
esac
# Live-rule detail belongs to an explicit open/action, never the focus hot path.
if { [ "${SENDER:-}" = "popup_refresh" ] || [ "${SENDER:-}" = "action_refresh" ]; } \
    && { [ "$SAVED_MODE" = "float" ] || [ "$SAVED_MODE" = "tile" ]; }; then
  LIVE_STATUS="unknown"
  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    RULES="$(run_with_timeout 1 "$YABAI_BIN" -m rule --list 2>/dev/null || true)"
    LIVE_STATUS="$(printf '%s\n' "$RULES" | "$JQ_BIN" -er --arg app "$APP_NAME" \
      --arg mode "$SAVED_MODE" --slurpfile state "$STATE_FILE" '
        if type != "array" then error("rules unavailable") else
          $state[0].window_defaults.apps[$app] as $saved
          | if ($saved.rule_label | type) != "string" or ($saved.app_regex | type) != "string"
            then "unknown"
            elif any(.[]; .label == $saved.rule_label and .app == $saved.app_regex
              and .manage == ($mode == "tile") and (.["sub-layer"] // "") == "")
            then "active" else "inactive" end
        end
      ' 2>/dev/null || printf unknown)"
  fi
  case "$LIVE_STATUS" in
    active) SAVED_LABEL="$SAVED_LABEL · Active" ;;
    inactive) SAVED_LABEL="$SAVED_LABEL · Not active — choose again" ;;
    *) SAVED_LABEL="$SAVED_LABEL · Live rule unverified" ;;
  esac
fi

FRONT_APP_LABEL_DRAWING="off"
if [ -n "$STACK_BADGE" ]; then
  FRONT_APP_LABEL_DRAWING="on"
fi

FRONT_APP_UPDATE=(
  "$NAME"
  "icon=$APP_ICON"
  icon.drawing=on
  "icon.color=$FRONT_APP_ICON_COLOR"
  icon.padding_left=8
  icon.padding_right=8
  "label=$STACK_BADGE"
  "label.drawing=$FRONT_APP_LABEL_DRAWING"
  background.drawing=on
  "background.color=$FRONT_APP_IDLE_BG"
  "background.border_width=$FRONT_APP_IDLE_BORDER_WIDTH"
  "background.border_color=$FRONT_APP_IDLE_BORDER_COLOR"
  --set front_app.header "label=$APP_NAME"
  --set front_app.state "icon=$STATE_ICON" "label=$STATE_LABEL"
  --set front_app.location "label=$LOCATION_LABEL"
)
if [ "$FRONT_APP_ACTION_ROWS" = "1" ]; then
  FRONT_APP_UPDATE+=(
    --set front_app.window.float "label=$FLOAT_ACTION_LABEL"
    --set front_app.window.fullscreen "label=$FULLSCREEN_ACTION_LABEL"
    --set front_app.window.topmost "label=$TOPMOST_ACTION_LABEL"
    --set front_app.window.sticky "label=$STICKY_ACTION_LABEL"
    --set front_app.preset.tile_here "label=$TILE_PRESET_LABEL"
    --set front_app.defaults.header "label=App Defaults · $APP_NAME"
    --set front_app.defaults.status "label=$SAVED_LABEL"
  )
  for binding in \
    "window.float:$FLOAT_ACTION_COMMAND" \
    window.adopt_space_mode:window-adopt-space-mode \
    window.fullscreen:window-toggle-fullscreen \
    window.sticky:window-toggle-sticky \
    window.topmost:window-toggle-topmost \
    window.center:window-center \
    preset.utility:window-preset-utility \
    preset.focus:window-preset-focus \
    preset.presentation:window-preset-presentation \
    preset.tile_here:window-preset-tile-here \
    move.float_space:window-space-float \
    move.display_prev:window-display-prev \
    move.display_next:window-display-next \
    move.space_prev:window-space-prev-wrap \
    move.space_next:window-space-next-wrap; do
    click_script=""
    if [ "$WINDOW_AVAILABLE" = "true" ]; then
      menu_action window "${binding#*:}"
      click_script="$CLICK_SCRIPT"
    fi
    FRONT_APP_UPDATE+=(--set "front_app.${binding%%:*}" "click_script=$click_script" "label.color=$WINDOW_COLOR")
  done
  for mode in float tile unset; do
    marker="○"
    [ "$mode" != "$SAVED_MODE" ] || marker="✓"
    menu_action default "$mode"
    FRONT_APP_UPDATE+=(--set "front_app.default.$mode" "icon=$marker" "click_script=$CLICK_SCRIPT")
  done
  for level in normal raised top unset; do
    marker="○"
    [ "$level" != "$SAVED_LEVEL" ] || marker="✓"
    menu_action level "$level"
    FRONT_APP_UPDATE+=(--set "front_app.level.$level" "icon=$marker" "click_script=$CLICK_SCRIPT")
  done
  for binding in hide:hide quit:quit force_quit:force-quit; do
    menu_action app "${binding#*:}"
    FRONT_APP_UPDATE+=(--set "front_app.${binding%%:*}" "click_script=$CLICK_SCRIPT")
  done
  if [ "${SENDER:-}" = "popup_refresh" ]; then
    FRONT_APP_UPDATE+=(--set front_app.feedback drawing=off)
  fi
fi

animate_set "${FRONT_APP_UPDATE[@]}" >/dev/null 2>&1 || true
