#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
if [[ -z "$YABAI_BIN" ]]; then
  echo "yabai not found in PATH." >&2
  exit 1
fi

target=${1:-current}
layout=${2:-}

if [[ -z "$layout" ]]; then
  echo "Usage: $0 <current|space_id> <bsp|stack|float>" >&2
  exit 1
fi

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN="$CONFIG_DIR/plugins/set_space_mode.sh"

if [[ -x "$PLUGIN" ]]; then
  "$PLUGIN" "$target" "$layout"
  exit 0
fi

if [[ "$target" == "current" ]]; then
  "$YABAI_BIN" -m space --layout "$layout"
else
  "$YABAI_BIN" -m space "$target" --layout "$layout"
fi
