#!/bin/bash
# Copy the Barista LaunchAgent assets and restart the supervisor.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
DEST_LAUNCH_DIR="$CONFIG_DIR/launch_agents"
REPO_LAUNCH_DIR="$REPO_ROOT/launch_agents"
PLIST_DEST="$HOME/Library/LaunchAgents/dev.barista.control.plist"
LABEL="gui/$(id -u)/dev.barista.control"

log() { printf '[barista-agent] %s\n' "$*"; }

if [[ ! -d "$REPO_LAUNCH_DIR" ]]; then
  log "Launch agent source directory not found: $REPO_LAUNCH_DIR"
  exit 1
fi

mkdir -p "$DEST_LAUNCH_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

log "Installing barista-launch.sh -> $DEST_LAUNCH_DIR"
install -m 755 "$REPO_LAUNCH_DIR/barista-launch.sh" "$DEST_LAUNCH_DIR/barista-launch.sh"

log "Installing dev.barista.control.plist -> $PLIST_DEST"
sed "s|\$HOME|$HOME|g" "$REPO_LAUNCH_DIR/dev.barista.control.plist" > "$PLIST_DEST"

log "Reloading dev.barista.control LaunchAgent"
launchctl bootout "$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl kickstart -k "$LABEL"

log "Barista LaunchAgent installed and restarted."

