#!/bin/bash
# Launch the unified Barista control panel (builds if needed).

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
GUI_DIR="$CONFIG_DIR/gui"
PANEL_BIN="$GUI_DIR/bin/config_menu"
LOG_FILE="${TMPDIR:-/tmp}barista_control_panel.log"

# Check if we're in the source directory (for development)
SOURCE_DIR="${HOME}/Code/barista"
if [ -x "${SOURCE_DIR}/build/bin/config_menu" ]; then
  echo "[barista] Launching control panel from source (logs: $LOG_FILE)"
  nohup "${SOURCE_DIR}/build/bin/config_menu" >"$LOG_FILE" 2>&1 &
  disown
  exit 0
fi

# Use installed binary
if [[ ! -x "$PANEL_BIN" ]]; then
  if [[ -d "$GUI_DIR" ]]; then
    echo "[barista] Building control panel…"
    cd "$GUI_DIR" || exit 1
    if command -v cmake &> /dev/null; then
      cd "${SOURCE_DIR:-$HOME/Code/barista}" || exit 1
      ./rebuild_gui.sh 2>&1 | tail -5
    else
      echo "[barista] CMake not found. Install with: brew install cmake" >&2
      exit 1
    fi
  else
    echo "[barista] GUI sources not found at $GUI_DIR" >&2
    exit 1
  fi
fi

echo "[barista] Launching control panel (logs: $LOG_FILE)"
nohup "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
disown

