#!/bin/bash

set -euo pipefail

MAPPER_SCRIPT="$HOME/.config/sketchybar/scripts/mouse_button_mapper.py"
LAUNCHER_SCRIPT="$HOME/.config/sketchybar/scripts/run_mouse_button_mapper.command"
LOG_FILE="$HOME/Library/Logs/barista-mouse-buttons.log"
TRACE_LOG="$HOME/Library/Logs/barista-mouse-buttons-bootstrap.log"
RUN_PATTERN="/Resources/Python.app/Contents/MacOS/Python ${MAPPER_SCRIPT}$"

log_trace() {
  printf '[mouse-bootstrap] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$TRACE_LOG"
}

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
touch "$TRACE_LOG"
log_trace "start"

if pgrep -f "$RUN_PATTERN" >/dev/null 2>&1; then
  log_trace "mapper already running"
  exit 0
fi

if [[ ! -x "$LAUNCHER_SCRIPT" ]]; then
  log_trace "launcher script missing: $LAUNCHER_SCRIPT"
  exit 1
fi

log_trace "launching via open Terminal command file"
/usr/bin/open -gja Terminal "$LAUNCHER_SCRIPT" >>"$TRACE_LOG" 2>&1 || true
sleep 1

if pgrep -f "$RUN_PATTERN" >/dev/null 2>&1; then
  log_trace "mapper launch detected"
else
  log_trace "mapper not detected after launch attempt"
fi
