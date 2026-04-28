#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for restricted Barista configuration." >&2
  exit 1
fi

if [ -f "$SCRIPT_DIR/machine_profile.py" ]; then
  exec python3 "$SCRIPT_DIR/machine_profile.py" apply --variant restricted-work "$@"
fi

exec python3 "$SCRIPT_DIR/restricted_config.py" apply "$@"
