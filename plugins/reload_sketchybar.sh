#!/bin/bash
# Relaunch SketchyBar via launchctl to avoid lock-file errors.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
AGENT="homebrew.mxcl.sketchybar"
HELPER="${CONFIG_DIR}/helpers/launch_agent_manager.sh"
LABEL="gui/$(id -u)/${AGENT}"
PLIST="${HOME}/Library/LaunchAgents/${AGENT}.plist"

if [[ -x "$HELPER" ]]; then
  exec "$HELPER" restart "$AGENT"
fi

if launchctl kickstart -k "$LABEL" >/dev/null 2>&1; then
  exit 0
fi

# Fallback to unload/load if kickstart failed (e.g., label missing)
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" >/dev/null 2>&1 || true
  launchctl load "$PLIST"
else
  echo "LaunchAgent plist not found: $PLIST" >&2
  exit 1
fi

