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
  --padding-left <int>  Bar left padding
  --padding-right <int> Bar right padding
  --margin <int>        Bar margin
  --y-offset <int>      Bar y-offset
  --border-width <int>  Bar border width
  --border-color <hex>  Bar border color
  --scale <float>       Widget scale
  --widget-corner <int> Widget corner radius
  --popup-padding <int> Popup horizontal padding
  --popup-corner <int>  Popup corner radius
  --popup-border <int>  Popup border width
  --popup-border-color <hex> Popup border color
  --popup-bg <hex>      Popup background color
  --popup-item-height <int> Popup row height (0 = auto)
  --popup-item-radius <int> Popup item corner radius
  --hover-color <hex>   Hover highlight color
  --hover-border-color <hex> Hover border color
  --hover-border-width <int> Hover border width
  --hover-curve <name>  Hover animation curve (sin, tanh, linear)
  --hover-duration <int> Hover animation duration
  --submenu-hover-color <hex> Submenu hover color
  --submenu-idle-color <hex> Submenu idle color
  --submenu-close-delay <float> Submenu close delay
  --group-bg <hex>      Widget group background color
  --group-border-color <hex> Widget group border color
  --group-border-width <int> Widget group border width
  --group-corner <int>  Widget group corner radius
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
    --padding-left)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_padding_left" "int" "$2")
      shift 2
      ;;
    --padding-right)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_padding_right" "int" "$2")
      shift 2
      ;;
    --margin)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_margin" "int" "$2")
      shift 2
      ;;
    --y-offset)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_y_offset" "float" "$2")
      shift 2
      ;;
    --border-width)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_border_width" "int" "$2")
      shift 2
      ;;
    --border-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("bar_border_color" "string" "$2")
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
    --popup-padding)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_padding" "int" "$2")
      shift 2
      ;;
    --popup-corner)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_corner_radius" "int" "$2")
      shift 2
      ;;
    --popup-border)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_border_width" "int" "$2")
      shift 2
      ;;
    --popup-border-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_border_color" "string" "$2")
      shift 2
      ;;
    --popup-bg)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_bg_color" "string" "$2")
      shift 2
      ;;
    --popup-item-height)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_item_height" "int" "$2")
      shift 2
      ;;
    --popup-item-radius)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("popup_item_corner_radius" "int" "$2")
      shift 2
      ;;
    --hover-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("hover_color" "string" "$2")
      shift 2
      ;;
    --hover-border-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("hover_border_color" "string" "$2")
      shift 2
      ;;
    --hover-border-width)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("hover_border_width" "int" "$2")
      shift 2
      ;;
    --hover-curve)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("hover_animation_curve" "string" "$2")
      shift 2
      ;;
    --hover-duration)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("hover_animation_duration" "int" "$2")
      shift 2
      ;;
    --submenu-hover-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("submenu_hover_color" "string" "$2")
      shift 2
      ;;
    --submenu-idle-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("submenu_idle_color" "string" "$2")
      shift 2
      ;;
    --submenu-close-delay)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("submenu_close_delay" "float" "$2")
      shift 2
      ;;
    --group-bg)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("group_bg_color" "string" "$2")
      shift 2
      ;;
    --group-border-color)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("group_border_color" "string" "$2")
      shift 2
      ;;
    --group-border-width)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("group_border_width" "int" "$2")
      shift 2
      ;;
    --group-corner)
      [[ -n "${2:-}" ]] || { usage; exit 1; }
      updates+=("group_corner_radius" "int" "$2")
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
