#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_UPDATE="$SCRIPT_DIR/runtime_update.sh"

usage() {
  echo "Usage: set_widget_color.sh <widget> <color>" >&2
}

widget="${1:-}"
color="${2:-}"

if [[ -z "$widget" || -z "$color" ]]; then
  usage
  exit 1
fi

if [[ ! -x "$RUNTIME_UPDATE" ]]; then
  echo "runtime_update.sh not found: $RUNTIME_UPDATE" >&2
  exit 1
fi

"$RUNTIME_UPDATE" widget-color "$widget" "$color"
