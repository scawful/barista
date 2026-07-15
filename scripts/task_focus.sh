#!/bin/bash

# Refresh and open the clock popup as the compact task-focus surface.

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
CALENDAR_SCRIPT="$CONFIG_DIR/plugins/calendar.sh"

if [ ! -x "$CALENDAR_SCRIPT" ]; then
  echo "task_focus: calendar plugin missing: $CALENDAR_SCRIPT" >&2
  exit 1
fi

"$CALENDAR_SCRIPT"
"$SKETCHYBAR_BIN" --trigger mouse.exited.global >/dev/null 2>&1 || true
"$SKETCHYBAR_BIN" --set clock popup.drawing=on
