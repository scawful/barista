#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
HELPER="$CONFIG_DIR/helpers/setup_permissions.sh"

if [[ -x "$HELPER" ]]; then
  exec "$HELPER"
fi

echo "setup_permissions.sh not found: $HELPER" >&2
exit 1
