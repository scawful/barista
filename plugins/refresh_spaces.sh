#!/bin/bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
SCRIPTS_DIR="$HOME/.config/scripts"

"$CONFIG_DIR/plugins/spaces_setup.sh"

if [ -x "$SCRIPTS_DIR/update_external_bar.sh" ]; then
  "$SCRIPTS_DIR/update_external_bar.sh" "${1:-}"
fi
