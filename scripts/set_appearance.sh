#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

usage() {
  cat <<'USAGE' >&2
Usage: set_appearance.sh [options]

Options:
  --height <int>        Bar height
  --corner <int>        Bar corner radius
  --color <hex>         Bar color (0xAARRGGBB or 0xRRGGBB)
  --blur <int>          Blur radius
  --scale <float>       Widget scale
  --widget-corner <int> Widget corner radius
  --theme <name>        Theme name
USAGE
}

updates=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --height)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_height" "int" "$2")
      shift 2
      ;;
    --corner)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("corner_radius" "int" "$2")
      shift 2
      ;;
    --color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_color" "string" "$2")
      shift 2
      ;;
    --blur)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("blur_radius" "int" "$2")
      shift 2
      ;;
    --scale)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("widget_scale" "float" "$2")
      shift 2
      ;;
    --widget-corner)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("widget_corner_radius" "int" "$2")
      shift 2
      ;;
    --theme)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("theme" "string" "$2")
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ ${#updates[@]} -eq 0 ]]; then
  usage
  exit 1
fi

mkdir -p "$CONFIG_DIR"

python3 - "$STATE_FILE" "${updates[@]}" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
args = sys.argv[2:]

if len(args) % 3 != 0:
    print("Invalid update payload", file=sys.stderr)
    sys.exit(1)

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

def parse_value(kind, value):
    if kind == "int":
        return int(value)
    if kind == "float":
        return float(value)
    return value

for i in range(0, len(args), 3):
    key, kind, value = args[i:i + 3]
    try:
        appearance[key] = parse_value(kind, value)
    except ValueError:
        print(f"Invalid value for {key}: {value}", file=sys.stderr)
        sys.exit(1)

data["appearance"] = appearance

os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PY

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi
