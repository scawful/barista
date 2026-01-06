#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

usage() {
  echo "Usage: set_space_icon.sh <space> <glyph|none>" >&2
}

space="${1:-}"
glyph="${2:-}"

if [[ -z "$space" || -z "$glyph" ]]; then
  usage
  exit 1
fi

mkdir -p "$CONFIG_DIR"

python3 - "$STATE_FILE" "$space" "$glyph" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
space = str(sys.argv[2])
glyph = sys.argv[3]

try:
    with open(state_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

space_icons = data.get("space_icons")
if not isinstance(space_icons, dict):
    space_icons = {}

if glyph.lower() in ("none", "null", ""):
    space_icons.pop(space, None)
else:
    space_icons[space] = glyph

data["space_icons"] = space_icons

os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
fi
