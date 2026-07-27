#!/bin/bash

# Toggle the clock task surface through its live click owner.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
POPUP_CLICK_SCRIPT="${BARISTA_POPUP_CLICK_SCRIPT:-$CONFIG_DIR/scripts/invoke_popup_click.sh}"

if [ ! -x "$POPUP_CLICK_SCRIPT" ]; then
  echo "task_focus: popup click helper missing: $POPUP_CLICK_SCRIPT" >&2
  exit 1
fi

export SKETCHYBAR_BIN
exec "$POPUP_CLICK_SCRIPT" clock
