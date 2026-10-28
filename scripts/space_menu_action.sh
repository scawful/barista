#!/bin/bash
# Apply a captured space action and keep its result visible in Control Center.
set -euo pipefail

_d="${0%/*}"
[ -z "$_d" ] && _d="."
[ -r "$_d/../plugins/lib/common.sh" ] && . "$_d/../plugins/lib/common.sh"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-${SCRIPTS_DIR:-$CONFIG_DIR/scripts}}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"

kind="${1:-}"
space_index="${2:-}"
space_id="${3:-}"
value="${4:-}"
root="${5:-control_center}"
if [[ ! "$space_index" =~ ^[1-9][0-9]*$ || ! "$space_id" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid captured space identity" >&2
  exit 1
fi
case "$kind:$value" in
  layout:float|layout:bsp|layout:stack)
    command=("$CONFIG_DIR/plugins/set_space_mode.sh" "$space_index" "$value")
    ;;
  arrange:balance|arrange:space-rotate|arrange:toggle-layout|arrange:space-mirror-x|arrange:space-mirror-y)
    command=("$SCRIPTS_DIR/yabai_control.sh" "$value")
    ;;
  *) echo "Invalid space menu action" >&2; exit 1 ;;
esac

export BARISTA_CONFIG_DIR="$CONFIG_DIR"
export BARISTA_TARGET_SPACE_INDEX="$space_index"
export BARISTA_TARGET_SPACE_ID="$space_id"

status=0
output="$("${command[@]}" 2>&1)" || status=$?
if [[ "$status" == "0" ]]; then
  # Selected layout and space identity are refreshed after the command succeeds.
  # Keep the root visible so repeated layout/arrangement choices are practical.
  NAME="$root" SENDER=popup_refresh BARISTA_CONTROL_CENTER_LAYOUT_ROWS=1 \
    "$CONFIG_DIR/plugins/control_center.sh" >/dev/null 2>&1 || true
  if [[ -n "$SKETCHYBAR_BIN" ]]; then
    "$SKETCHYBAR_BIN" --set cc.feedback drawing=off label= \
      --set cc.more popup.drawing=off --set cc.settings popup.drawing=off \
      --set "$root" popup.drawing=on >/dev/null 2>&1 || true
  fi
else
  [[ -n "$output" ]] || output="Space action failed (exit $status)"
  printf '%s\n' "$output" >&2
  feedback="${output%%$'\n'*}"
  feedback="${feedback//$'\t'/ }"
  feedback="${feedback//$'\r'/ }"
  feedback="${feedback:0:160}"
  if [[ -n "$SKETCHYBAR_BIN" ]]; then
    "$SKETCHYBAR_BIN" --set cc.feedback drawing=on "label=$feedback" \
      --set cc.more popup.drawing=off --set cc.settings popup.drawing=off \
      --set "$root" popup.drawing=on >/dev/null 2>&1 || true
  fi
fi
exit "$status"
