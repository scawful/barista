#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
ICON_MAP="$CONFIG_DIR/icon_map.json"

usage() {
  echo "Usage: set_app_icon.sh <app_name> <glyph|none>" >&2
}

app_name="${1:-}"
glyph="${2:-}"

if [[ -z "$app_name" || -z "$glyph" ]]; then
  usage
  exit 1
fi

mkdir -p "$CONFIG_DIR"

python3 - "$ICON_MAP" "$app_name" "$glyph" <<'PY'
import json
import os
import sys

icon_map = sys.argv[1]
app_name = sys.argv[2]
glyph = sys.argv[3]

try:
    with open(icon_map, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

if glyph.lower() in ("none", "null", ""):
    data.pop(app_name, None)
else:
    data[app_name] = glyph

os.makedirs(os.path.dirname(icon_map), exist_ok=True)
with open(icon_map, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
fi
