#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/machine_profile.py" ]; then
  exec python3 "$SCRIPT_DIR/machine_profile.py" capabilities "$@"
fi

has_command() {
  command -v "$1" >/dev/null 2>&1
}

for capability in sketchybar yabai skhd jq python3 swift xcodebuild open brew; do
  if has_command "$capability"; then
    printf 'capability.%s=1\n' "$capability"
  else
    printf 'capability.%s=0\n' "$capability"
  fi
done
