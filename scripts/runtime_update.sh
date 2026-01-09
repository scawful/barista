#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "state.json not found: $STATE_FILE" >&2
  exit 1
fi

command="${1:-}"
shift || true

if [[ -z "$command" ]]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$STATE_FILE" "$command" "$@" <<'PY'
import json
import os
import sys

state_file = sys.argv[1]
command = sys.argv[2]
args = sys.argv[3:]

def usage(msg=None):
    if msg:
        print(msg, file=sys.stderr)
    print("Commands:", file=sys.stderr)
    print("  widget-color <widget> <color>", file=sys.stderr)
    print("  widget-toggle <widget> <on|off>", file=sys.stderr)
    print("  theme <name>", file=sys.stderr)
    print("  bar-height <height>", file=sys.stderr)
    print("  bar-color <color> [blur]", file=sys.stderr)
    print("  icon <name> <glyph|none>", file=sys.stderr)
    print("  space-icon <space> <glyph|none>", file=sys.stderr)
    sys.exit(1)

try:
    with open(state_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    usage(f"Failed to read state.json: {exc}")

if not isinstance(data, dict):
    usage("state.json root must be an object")

def ensure_dict(key):
    if not isinstance(data.get(key), dict):
        data[key] = {}
    return data[key]

if command == "widget-color":
    if len(args) < 2:
        usage("widget-color requires <widget> <color>")
    widget, color = args[0], args[1]
    ensure_dict("widget_colors")[widget] = color
elif command == "widget-toggle":
    if len(args) < 2:
        usage("widget-toggle requires <widget> <on|off>")
    widget, value = args[0], args[1].lower()
    enabled = value in ("1", "true", "on", "yes")
    ensure_dict("widgets")[widget] = enabled
elif command == "theme":
    if len(args) < 1:
        usage("theme requires <name>")
    ensure_dict("appearance")["theme"] = args[0]
elif command == "bar-height":
    if len(args) < 1:
        usage("bar-height requires <height>")
    try:
        height = int(args[0])
    except ValueError:
        usage("bar-height requires an integer")
    ensure_dict("appearance")["bar_height"] = height
elif command == "bar-color":
    if len(args) < 1:
        usage("bar-color requires <color> [blur]")
    ensure_dict("appearance")["bar_color"] = args[0]
    if len(args) > 1:
        try:
            blur = int(args[1])
        except ValueError:
            usage("bar-color blur must be an integer")
        ensure_dict("appearance")["blur_radius"] = blur
elif command == "icon":
    if len(args) < 2:
        usage("icon requires <name> <glyph|none>")
    name, glyph = args[0], args[1]
    icons = ensure_dict("icons")
    if glyph in ("", "none"):
        icons.pop(name, None)
    else:
        icons[name] = glyph
elif command == "space-icon":
    if len(args) < 2:
        usage("space-icon requires <space> <glyph|none>")
    space, glyph = str(args[0]), args[1]
    space_icons = ensure_dict("space_icons")
    if glyph in ("", "none"):
        space_icons.pop(space, None)
    else:
        space_icons[space] = glyph
else:
    usage(f"Unknown command: {command}")

tmp_file = state_file + ".tmp"
with open(tmp_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(tmp_file, state_file)
PY
elif command -v lua >/dev/null 2>&1; then
  lua "$CONFIG_DIR/scripts/runtime_update.lua" "$command" "$@"
else
  echo "runtime_update: python3 or lua is required" >&2
  exit 1
fi

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi
