#!/usr/bin/env bash
set -euo pipefail

HEIGHT="${1:-}"

if [[ -z "$HEIGHT" ]]; then
  echo "Usage: $0 <height>" >&2
  exit 1
fi

YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
if [ -z "$YABAI_BIN" ] || ! command -v "$YABAI_BIN" >/dev/null 2>&1; then
  exit 0
fi

"$YABAI_BIN" -m config external_bar all:"$HEIGHT":0 >/dev/null 2>&1
