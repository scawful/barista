#!/usr/bin/env bash
set -euo pipefail

HEIGHT="${1:-}"

if [[ -z "$HEIGHT" ]]; then
  echo "Usage: $0 <height>" >&2
  exit 1
fi

if ! command -v yabai >/dev/null 2>&1; then
  exit 0
fi

yabai -m config external_bar all:"$HEIGHT":0 >/dev/null 2>&1 || true
