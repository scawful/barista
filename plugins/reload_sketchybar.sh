#!/bin/bash
# Relaunch SketchyBar via launchctl to avoid lock-file errors.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
AGENT="homebrew.mxcl.sketchybar"
HELPER="${CONFIG_DIR}/helpers/launch_agent_manager.sh"
LABEL="gui/$(id -u)/${AGENT}"
PLIST="${HOME}/Library/LaunchAgents/${AGENT}.plist"
SPACE_REPAIR_DELAY="${BARISTA_SPACE_REPAIR_DELAY:-1.0}"

schedule_space_repair() {
  local refresh_script="${CONFIG_DIR}/plugins/refresh_spaces.sh"
  [ -f "$refresh_script" ] || return 0
  nohup env CONFIG_DIR="$CONFIG_DIR" BARISTA_CONFIG_DIR="$CONFIG_DIR" bash -lc \
    "sleep ${SPACE_REPAIR_DELAY}; \"${refresh_script}\" >/dev/null 2>&1 || true" >/dev/null 2>&1 &
}

if [[ -x "$HELPER" ]]; then
  "$HELPER" restart "$AGENT"
  schedule_space_repair
  exit 0
fi

if launchctl kickstart -k "$LABEL" >/dev/null 2>&1; then
  schedule_space_repair
  exit 0
fi

# Fallback to unload/load if kickstart failed (e.g., label missing)
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" >/dev/null 2>&1 || true
  launchctl load "$PLIST"
  schedule_space_repair
else
  echo "LaunchAgent plist not found: $PLIST" >&2
  exit 1
fi
