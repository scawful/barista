#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_UPDATE="$SCRIPT_DIR/runtime_update.sh"

usage() {
  echo "Usage: widget_toggle.sh <widget> <on|off>" >&2
}

widget="${1:-}"
state="${2:-}"

if [[ -z "$widget" || -z "$state" ]]; then
  usage
  exit 1
fi

if [[ ! -x "$RUNTIME_UPDATE" ]]; then
  echo "runtime_update.sh not found: $RUNTIME_UPDATE" >&2
  exit 1
fi

"$RUNTIME_UPDATE" widget-toggle "$widget" "$state"
