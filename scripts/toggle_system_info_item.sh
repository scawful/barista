#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

usage() {
  echo "Usage: toggle_system_info_item.sh <item> <on|off>" >&2
}

item="${1:-}"
state="${2:-}"

if [[ -z "$item" || -z "$state" ]]; then
  usage
  exit 1
fi

mkdir -p "$CONFIG_DIR"

python3 - "$STATE_FILE" "$item" "$state" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
item = sys.argv[2]
value = sys.argv[3].lower()

enabled = value in ("1", "true", "yes", "on")

try:
    with open(state_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

items = data.get("system_info_items")
if not isinstance(items, dict):
    items = {}

items[item] = enabled
data["system_info_items"] = items

os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi
