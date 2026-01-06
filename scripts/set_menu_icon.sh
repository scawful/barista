#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_UPDATE="$SCRIPT_DIR/runtime_update.sh"

usage() {
  echo "Usage: set_menu_icon.sh <icon_name> <glyph|none>" >&2
}

icon_name="${1:-}"
glyph="${2:-}"

if [[ -z "$icon_name" || -z "$glyph" ]]; then
  usage
  exit 1
fi

if [[ ! -x "$RUNTIME_UPDATE" ]]; then
  echo "runtime_update.sh not found: $RUNTIME_UPDATE" >&2
  exit 1
fi

"$RUNTIME_UPDATE" icon "$icon_name" "$glyph"
