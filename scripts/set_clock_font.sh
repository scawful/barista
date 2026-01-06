#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

usage() {
  echo "Usage: set_clock_font.sh <style>" >&2
}

style="${1:-}"

if [[ -z "$style" ]]; then
  usage
  exit 1
fi

mkdir -p "$CONFIG_DIR"

python3 - "$STATE_FILE" "$style" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
style = sys.argv[2]

try:
    with open(state_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

appearance = data.get("appearance")
if not isinstance(appearance, dict):
    appearance = {}

appearance["clock_font_style"] = style

data["appearance"] = appearance

os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi
