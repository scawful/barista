#!/usr/bin/env bash
set -euo pipefail

SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"
LOG_FILE="${SKETCHYBAR_ERR_LOG:-/opt/homebrew/var/log/sketchybar/sketchybar.err.log}"

if [[ ! -x "$SKETCHYBAR_BIN" ]]; then
  SKETCHYBAR_BIN="$(command -v sketchybar || true)"
fi

if [[ -z "$SKETCHYBAR_BIN" ]]; then
  echo "sketchybar not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Filter out known noisy lines while preserving real errors.
exec "$SKETCHYBAR_BIN" 2> >(grep -Ev "MallocStackLogging|Item not found" >> "$LOG_FILE" || true)
