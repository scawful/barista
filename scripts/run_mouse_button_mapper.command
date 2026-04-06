#!/bin/zsh

set -euo pipefail

PYTHON_BIN="$HOME/.local/share/barista-mouse-buttons/.venv/bin/python3.14"
MAPPER_SCRIPT="$HOME/.config/sketchybar/scripts/mouse_button_mapper.py"
LOG_FILE="$HOME/Library/Logs/barista-mouse-buttons.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

nohup "$PYTHON_BIN" "$MAPPER_SCRIPT" >>"$LOG_FILE" 2>&1 &
