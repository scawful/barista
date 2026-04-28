#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/restricted_config.py" ]; then
  exec python3 "$SCRIPT_DIR/restricted_config.py" work-apps "$@"
fi

exec "$SCRIPT_DIR/setup_machine.sh" --apps-only "$@"
