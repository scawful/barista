#!/bin/bash
# Rebuild helpers/GUI and reload SketchyBar safely.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
HELPERS_DIR="$CONFIG_DIR/helpers"
GUI_DIR="$CONFIG_DIR/gui"
LAUNCH_HELPER="$CONFIG_DIR/helpers/launch_agent_manager.sh"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"

RELOAD_ONLY=0
if [[ "${1:-}" == "--reload-only" ]]; then
  RELOAD_ONLY=1
fi

log() {
  printf '[barista] %s\n' "$*"
}

if [[ $RELOAD_ONLY -eq 0 ]]; then
  if [[ -d "$HELPERS_DIR" ]]; then
    log "Building helpers..."
    /usr/bin/make -C "$HELPERS_DIR" all >/tmp/barista_build_helpers.log 2>&1 || {
      cat /tmp/barista_build_helpers.log >&2
      exit 1
    }
  fi

  if [[ -d "$GUI_DIR" ]]; then
    log "Building GUI tools..."
    /usr/bin/make -C "$GUI_DIR" all >/tmp/barista_build_gui.log 2>&1 || {
      cat /tmp/barista_build_gui.log >&2
      exit 1
    }
  fi
fi

if [[ -x "$LAUNCH_HELPER" ]]; then
  log "Restarting SketchyBar via launch_agent_manager..."
  "$LAUNCH_HELPER" restart homebrew.mxcl.sketchybar
else
  log "launch_agent_manager.sh not found. Falling back to --reload."
  "$SKETCHYBAR_BIN" --reload
fi

