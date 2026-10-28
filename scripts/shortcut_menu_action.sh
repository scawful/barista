#!/usr/bin/env bash
# Keep shortcut service failures visible instead of closing the menu on error.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
root="${1:-control_center}"
status=0
output="$("$SCRIPT_DIR/toggle_yabai_shortcuts.sh" toggle 2>&1)" || status=$?
if [[ "$status" == 0 ]]; then
  NAME="$root" SENDER=popup_refresh BARISTA_CONTROL_CENTER_LAYOUT_ROWS=1 \
    "$CONFIG_DIR/plugins/control_center.sh" >/dev/null 2>&1 || true
  if [[ -n "$SKETCHYBAR_BIN" ]]; then
    "$SKETCHYBAR_BIN" --set cc.feedback drawing=off label= \
      --set cc.more popup.drawing=off --set cc.settings popup.drawing=on \
      --set "$root" popup.drawing=on >/dev/null 2>&1 || true
  fi
else
  [[ -n "$output" ]] || output="Shortcut action failed (exit $status)"
  printf '%s\n' "$output" >&2
  feedback="${output##*$'\n'}"
  feedback="${feedback//$'\t'/ }"
  feedback="${feedback//$'\r'/ }"
  if [[ -n "$SKETCHYBAR_BIN" ]]; then
    "$SKETCHYBAR_BIN" --set cc.feedback drawing=on "label=${feedback:0:160}" \
      --set cc.more popup.drawing=off --set cc.settings popup.drawing=off \
      --set "$root" popup.drawing=on >/dev/null 2>&1 || true
  fi
fi
exit "$status"
