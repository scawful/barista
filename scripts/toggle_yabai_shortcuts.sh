#!/usr/bin/env bash
# Compatibility entry point: one owner for shortcut state and service actions.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/toggle_shortcuts.sh" "$@"
