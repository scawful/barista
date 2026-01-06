#!/bin/bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
MODE="${2:-float}"
TARGET="${1:-current}"

JQ_BIN="$(command -v jq 2>/dev/null || true)"

if [ "$TARGET" = "current" ]; then
  if command -v yabai >/dev/null 2>&1 && [ -n "$JQ_BIN" ]; then
    TARGET=$(yabai -m query --spaces --space | "$JQ_BIN" -r '.index' 2>/dev/null || true)
  fi
fi

if [ -z "$TARGET" ]; then
  echo "Unable to resolve space index" >&2
  exit 1
fi

normalize_mode() {
  case "$1" in
    float|floating)
      printf 'float'
      ;;
    stack|stacked)
      printf 'stack'
      ;;
    bsp|tile|tiling)
      printf 'bsp'
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

MODE=$(normalize_mode "$MODE")

update_state() {
  python3 - "$STATE_FILE" "$TARGET" "$MODE" <<'PY'
import json, os, sys
state_path, space, mode = sys.argv[1:4]
try:
    with open(state_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
space_modes = data.get("space_modes")
if not isinstance(space_modes, dict):
    space_modes = {}
data["space_modes"] = space_modes
if mode == "float":
    space_modes.pop(str(space), None)
else:
    space_modes[str(space)] = mode
with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False)
PY
}

apply_layout() {
  if ! command -v yabai >/dev/null 2>&1; then
    return
  fi
  if [ "$MODE" = "float" ]; then
    yabai -m space "$TARGET" --layout float >/dev/null 2>&1 || true
    yabai -m space "$TARGET" --toggle float >/dev/null 2>&1 || true
  else
    yabai -m space "$TARGET" --layout "$MODE" >/dev/null 2>&1 || true
  fi
}

update_state
apply_layout
sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
sketchybar --trigger yabai_status_refresh >/dev/null 2>&1 || true
