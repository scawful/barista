#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-volume}"
VOLUME_SCRIPT="${_d}/volume.sh"

popup_is_open() {
  local query
  query="$(sketchybar --query "$NAME" 2>/dev/null || true)"
  [ -n "$query" ] || return 1
  printf '%s' "$query" | python3 -c 'import json, sys; data = json.load(sys.stdin); raise SystemExit(0 if data.get("popup", {}).get("drawing") == "on" else 1)'
}

if popup_is_open; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

"$VOLUME_SCRIPT" >/dev/null 2>&1 || true
sketchybar --set "$NAME" popup.drawing=on
