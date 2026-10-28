#!/bin/bash
# Compatibility shim: space topology is now managed by plugins/simple_spaces.sh.
set -euo pipefail
CONFIG_DIR="${CONFIG_DIR:-${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/simple_spaces.sh" ]; then
  exec "$SCRIPT_DIR/simple_spaces.sh" "$@"
fi
exec "$CONFIG_DIR/plugins/simple_spaces.sh" "$@"
