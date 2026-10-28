#!/bin/bash
# control_center.sh - SketchyBar Control Center widget update script
# Shows layout mode and shortcut state for the active control-center surface

set -euo pipefail

PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"
NAME="${NAME:-control_center}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
STATE_FILE="${CONFIG_DIR}/state.json"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
if [[ -z "$SKETCHYBAR_BIN" ]]; then
  SKETCHYBAR_BIN="/opt/homebrew/opt/sketchybar/bin/sketchybar"
fi

YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
LAYOUT_ROWS="${BARISTA_CONTROL_CENTER_LAYOUT_ROWS:-1}"

set_popup_drawing() {
  local drawing="$1"
  local args=(--set cc.settings popup.drawing=off)
  if [[ "$LAYOUT_ROWS" == "1" ]]; then
    args+=(--set cc.more popup.drawing=off)
  fi
  "$SKETCHYBAR_BIN" "${args[@]}" --set "$NAME" "popup.drawing=$drawing" >/dev/null 2>&1 || true
}

case "${SENDER:-}" in
  "mouse.clicked")
    set_popup_drawing toggle
    exit 0
    ;;
  "mouse.entered")
    highlight_with_timeout "$NAME" "$(anchor_hover_props)" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited.global")
    set_popup_drawing off
    clear_highlight "$NAME" "$(anchor_idle_props)"
    exit 0
    ;;
esac

if [[ "${BARISTA_CONTROL_CENTER_ACTION:-}" == "click" ]]; then
  set_popup_drawing toggle
  exit 0
fi

# One bounded query owns both the displayed identity and the action target.
# Never publish a selected layout or a live action from partial/invalid data.
read_current_space() {
  [[ "$WM_ENABLED" == "1" && -n "$YABAI_BIN" && -n "$JQ_BIN" ]] || return 0
  local snapshot fields
  snapshot="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces --space 2>/dev/null)" || return 0
  fields="$(printf '%s' "$snapshot" | "$JQ_BIN" -er '
    select(type == "object")
    | select((.index | type) == "number" and (.display | type) == "number" and (.id | type) == "number")
    | select(.index > 0 and .index == (.index | floor) and .display > 0 and .display == (.display | floor) and .id > 0 and .id == (.id | floor))
    | select(.type == "float" or .type == "bsp" or .type == "stack")
    | [.index, .display, .type, .id] | @tsv
  ' 2>/dev/null)" || return 0
  IFS=$'\t' read -r SPACE_INDEX DISPLAY_INDEX SPACE_LAYOUT SPACE_ID <<< "$fields"
}

normalize_window_manager_mode() {
  local mode="${1:-auto}"
  mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    off|false|none|disable|disabled) echo "disabled" ;;
    optional|opt) echo "optional" ;;
    required|require|enabled|enable|on) echo "required" ;;
    *) echo "${mode:-auto}" ;;
  esac
}

read_window_manager_mode() {
  if [[ -n "${BARISTA_WINDOW_MANAGER_MODE:-}" ]]; then
    normalize_window_manager_mode "$BARISTA_WINDOW_MANAGER_MODE"
    return
  fi
  if [[ -f "$STATE_FILE" ]]; then
    local mode
    mode="$(read_state_json_string "$STATE_FILE" "modes.window_manager" "" || true)"
    if [[ -n "$mode" ]]; then
      normalize_window_manager_mode "$mode"
      return
    fi
  fi
  echo "auto"
}

resolve_window_manager_flags() {
  local mode has_yabai has_skhd yabai_running skhd_running enabled required
  mode="$(read_window_manager_mode)"
  has_yabai=0
  has_skhd=0
  yabai_running=0
  skhd_running=0
  [[ -n "$YABAI_BIN" && -x "$YABAI_BIN" ]] && has_yabai=1
  command -v skhd >/dev/null 2>&1 && has_skhd=1
  pgrep -x yabai >/dev/null 2>&1 && yabai_running=1
  pgrep -x skhd >/dev/null 2>&1 && skhd_running=1

  case "$mode" in
    disabled)
      enabled=0
      required=0
      ;;
    optional)
      enabled=$yabai_running
      required=0
      ;;
    required)
      enabled=$has_yabai
      required=1
      ;;
    *)
      enabled=$has_yabai
      required=$has_yabai
      ;;
  esac

  echo "$mode:$enabled:$required:$has_yabai:$has_skhd:$yabai_running:$skhd_running"
}

# Main
IFS=: read -r WM_MODE WM_ENABLED WM_REQUIRED _ _ WM_YABAI_RUNNING WM_SKHD_RUNNING <<EOF
$(resolve_window_manager_flags)
EOF
SPACE_INDEX=""
DISPLAY_INDEX=""
SPACE_LAYOUT=""
SPACE_ID=""
read_current_space

health="healthy"
if [[ "$WM_REQUIRED" -eq 1 && ( "$WM_YABAI_RUNNING" -ne 1 || "$WM_SKHD_RUNNING" -ne 1 ) ]]; then
  health="degraded"
fi
if [[ "$health" == "healthy" ]]; then
  ICON="󰕮"
  ICON_COLOR="0xffa6e3a1"
else
  ICON="󰕯"
  ICON_COLOR="0xfff38ba8"
fi

LABEL="---"
case "$SPACE_LAYOUT" in
  bsp) LABEL="Tile" ;;
  stack) LABEL="Stack" ;;
  float) LABEL="Manual" ;;
esac
[[ "$WM_ENABLED" == "1" ]] || LABEL="Bar"

ANCHOR=(--set "$NAME" "icon=$ICON" "icon.color=$ICON_COLOR" "label=$LABEL" label.color=0xffcdd6f4)
UPDATES=()
if [[ "$WM_ENABLED" == "1" && "$LAYOUT_ROWS" == "1" ]]; then
  SPACE_HEADER="Space unavailable"
  [[ -z "$SPACE_INDEX" ]] || SPACE_HEADER="Space $SPACE_INDEX · Display $DISPLAY_INDEX"
  UPDATES+=(--set cc.header "label=$SPACE_HEADER" --set cc.layout_ops_header "label=$SPACE_HEADER")
  for mode in float bsp stack; do
    case "$mode" in
      float) mode_label="Manual" ;;
      bsp) mode_label="Tile" ;;
      stack) mode_label="Stack" ;;
    esac
    marker="○"
    color="0xff6c7086"
    action=""
    if [[ -n "$SPACE_INDEX" ]]; then
      color="0xffcdd6f4"
      [[ "$SPACE_LAYOUT" != "$mode" ]] || { marker="●"; color="0xffa6e3a1"; }
      printf -v action 'BARISTA_CONFIG_DIR=%q %q layout %s %s %s %q' \
        "$CONFIG_DIR" "$CONFIG_DIR/scripts/space_menu_action.sh" "$SPACE_INDEX" "$SPACE_ID" "$mode" "$NAME"
    fi
    UPDATES+=(--set "cc.layout.$mode" "label=$marker $mode_label" "label.color=$color" "click_script=$action")
  done
  for operation in balance rotate toggle flipx flipy; do
    case "$operation" in
      balance) command_name="balance" ;;
      rotate) command_name="space-rotate" ;;
      toggle) command_name="toggle-layout" ;;
      flipx) command_name="space-mirror-x" ;;
      flipy) command_name="space-mirror-y" ;;
    esac
    action=""
    if [[ -n "$SPACE_INDEX" ]]; then
      printf -v action 'BARISTA_CONFIG_DIR=%q BARISTA_SCRIPTS_DIR=%q %q arrange %s %s %s %q' \
        "$CONFIG_DIR" "$SCRIPTS_DIR" "$CONFIG_DIR/scripts/space_menu_action.sh" "$SPACE_INDEX" "$SPACE_ID" "$command_name" "$NAME"
    fi
    UPDATES+=(--set "cc.layout_ops.$operation" "click_script=$action")
  done

fi

for mode in auto required optional disabled; do
  case "$mode" in
    auto) mode_label="Auto Detect" ;;
    required) mode_label="Always" ;;
    optional) mode_label="When Yabai Runs" ;;
    disabled) mode_label="Hidden" ;;
  esac
  marker="○"
  [[ "$WM_MODE" != "$mode" ]] || marker="●"
  UPDATES+=(--set "cc.mode.$mode" "label=$marker $mode_label")
done

DOCK_LABEL="Dock: macOS"
[[ ! -f "${BARISTA_AGENT_PLIST:-$HOME/Library/LaunchAgents/dev.barista.agent.plist}" ]] || DOCK_LABEL="Dock: Barista"
UPDATES+=(--set cc.dock "label=$DOCK_LABEL")

if [[ "$WM_ENABLED" == "1" && "$LAYOUT_ROWS" == "1" ]]; then
  if [[ "$WM_SKHD_RUNNING" -eq 1 ]]; then
    UPDATES+=(--set cc.yabai.shortcuts "label=Shortcuts: On" icon.color=0xffa6e3a1)
  else
    UPDATES+=(--set cc.yabai.shortcuts "label=Shortcuts: Off" icon.color=0xfff38ba8)
  fi
fi

ROW_CACHE="${TMPDIR:-/tmp}/sketchybar_control_center/${NAME}.rows"
rows_key="$(printf '%s\n' "${UPDATES[@]}")"
case "${SENDER:-}" in
  routine|space_active_refresh|space_mode_refresh|system_woke)
    # Background refreshes publish the anchor alone first so a space switch
    # is not held behind repainting closed popup rows; unchanged rows are
    # not resent at all.
    "$SKETCHYBAR_BIN" "${ANCHOR[@]}"
    cached=""
    [[ ! -r "$ROW_CACHE" ]] || cached="$(<"$ROW_CACHE")"
    [[ "$cached" != "$rows_key" ]] || exit 0
    "$SKETCHYBAR_BIN" "${UPDATES[@]}"
    ;;
  *)
    "$SKETCHYBAR_BIN" "${ANCHOR[@]}" "${UPDATES[@]}"
    ;;
esac
mkdir -p "${ROW_CACHE%/*}" && printf '%s\n' "$rows_key" > "$ROW_CACHE"
