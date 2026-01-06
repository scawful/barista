#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN="$CONFIG_DIR/plugins/bar_logs.sh"

if [[ -x "$PLUGIN" ]]; then
  exec "$PLUGIN" "$@"
fi

echo "bar_logs.sh not found: $PLUGIN" >&2
exit 1
