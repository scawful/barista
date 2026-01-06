#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOGGLE_SCRIPT="$SCRIPT_DIR/toggle_shortcuts.sh"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

usage() {
  echo "Usage: toggle_yabai_shortcuts.sh <on|off|toggle|status|restart>" >&2
}

command="${1:-}"
if [[ -z "$command" ]]; then
  usage
  exit 1
fi

case "$command" in
  on|off|start|stop|toggle|status|restart)
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ ! -x "$TOGGLE_SCRIPT" ]]; then
  echo "toggle_shortcuts.sh not found: $TOGGLE_SCRIPT" >&2
  exit 1
fi

case "$command" in
  status)
    "$TOGGLE_SCRIPT" status || true
    ;;
  restart)
    "$TOGGLE_SCRIPT" off || true
    "$TOGGLE_SCRIPT" on || true
    ;;
  *)
    if ! "$TOGGLE_SCRIPT" "$command"; then
      echo "toggle_shortcuts.sh failed" >&2
    fi
    ;;
esac

running=false
if pgrep -x skhd >/dev/null 2>&1; then
  running=true
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$STATE_FILE" "$running" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
running = sys.argv[2].lower() in ("1", "true", "yes", "on")

try:
    with open(state_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

toggles = data.get("toggles")
if not isinstance(toggles, dict):
    toggles = {}

toggles["yabai_shortcuts"] = running

data["toggles"] = toggles
os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY
fi
