#!/bin/bash
# control_center.sh - SketchyBar Control Center widget update script
# Shows layout mode and shortcut state for the active control-center surface

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"
NAME="${NAME:-control_center}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${CONFIG_DIR}/state.json"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
if [[ -z "$SKETCHYBAR_BIN" ]]; then
  SKETCHYBAR_BIN="/opt/homebrew/opt/sketchybar/bin/sketchybar"
fi

case "${SENDER:-}" in
  "mouse.entered")
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    "$SKETCHYBAR_BIN" --set "$NAME" popup.drawing=off >/dev/null 2>&1 || true
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
esac

# Check if yabai is running and get layout
get_layout() {
  if [[ "${1:-1}" != "1" ]]; then
    echo "Bar"
    return
  fi
  if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "---"
    return
  fi
  local layout
  if ! layout=$(run_with_timeout 1 yabai -m query --spaces --space 2>/dev/null | jq -r '.type // "unknown"' 2>/dev/null); then
    layout="unknown"
  fi
  case "$layout" in
    bsp) echo "BSP" ;;
    stack) echo "Stack" ;;
    float) echo "Float" ;;
    *) echo "---" ;;
  esac
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
  if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
    local mode
    mode="$(jq -r '.modes.window_manager // empty' "$STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$mode" && "$mode" != "null" ]]; then
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
  command -v yabai >/dev/null 2>&1 && has_yabai=1
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
IFS=: read -r WM_MODE WM_ENABLED WM_REQUIRED WM_HAS_YABAI WM_HAS_SKHD WM_YABAI_RUNNING WM_SKHD_RUNNING <<EOF
$(resolve_window_manager_flags)
EOF
layout=$(get_layout "$WM_ENABLED")
health="healthy"
if [[ "$WM_REQUIRED" -eq 1 && ( "$WM_YABAI_RUNNING" -ne 1 || "$WM_SKHD_RUNNING" -ne 1 ) ]]; then
  health="degraded"
fi

# Icon based on health
if [[ "$health" == "healthy" ]]; then
  ICON="󰕮"
  ICON_COLOR="0xffa6e3a1"  # Green
else
  ICON="󰕯"
  ICON_COLOR="0xfff38ba8"  # Red
fi

# Build label (just layout mode, no dirty count)
LABEL="$layout"

# Update widget
"$SKETCHYBAR_BIN" --set "$NAME" \
  icon="$ICON" \
  icon.color="$ICON_COLOR" \
  label="$LABEL" \
  label.color="0xffcdd6f4"

set_popup_item() {
  local item="$1"
  shift
  "$SKETCHYBAR_BIN" --set "$item" "$@" >/dev/null 2>&1 || true
}

if [[ "$WM_SKHD_RUNNING" -eq 1 ]]; then
  set_popup_item "cc.yabai.shortcuts" "label=Yabai Shortcuts: On" "icon.color=0xffa6e3a1"
else
  set_popup_item "cc.yabai.shortcuts" "label=Yabai Shortcuts: Off" "icon.color=0xfff38ba8"
fi
