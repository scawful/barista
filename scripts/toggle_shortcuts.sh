#!/usr/bin/env bash
set -euo pipefail

command=${1:-status}
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

is_running() {
  pgrep -x skhd >/dev/null 2>&1
}

update_state() {
  local running="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$CONFIG_DIR" 2>/dev/null || true
  python3 - "$STATE_FILE" "$running" <<'PY' || true
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
}

sync_state() {
  if is_running; then
    update_state true
  else
    update_state false
  fi
}

start_skhd() {
  if skhd --start-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services start skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

stop_skhd() {
  if skhd --stop-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services stop skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

case "$command" in
  toggle)
    if is_running; then
      stop_skhd && echo "skhd stopped" || echo "failed to stop skhd" >&2
    else
      start_skhd && echo "skhd started" || echo "failed to start skhd" >&2
    fi
    sync_state
    ;;
  on|start)
    start_skhd && echo "skhd started" || echo "failed to start skhd" >&2
    sync_state
    ;;
  off|stop)
    stop_skhd && echo "skhd stopped" || echo "failed to stop skhd" >&2
    sync_state
    ;;
  status)
    if is_running; then
      echo "skhd running"
    else
      echo "skhd stopped"
    fi
    sync_state
    ;;
  *)
    echo "Usage: $0 {toggle|on|off|status}" >&2
    exit 1
    ;;
 esac
