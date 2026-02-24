#!/usr/bin/env bash
set -euo pipefail

# Focus the display under the mouse before toggling a popup.
# This prevents cross-monitor popup mismatches when display focus lags.

ITEM_NAME="${1:-${NAME:-}}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"

if [[ -n "${YABAI_BIN}" && -x "${YABAI_BIN}" ]]; then
  if [[ -n "${JQ_BIN}" && -x "${JQ_BIN}" ]]; then
    target_display="$("${YABAI_BIN}" -m query --displays --display mouse 2>/dev/null | "${JQ_BIN}" -r '.index // empty' 2>/dev/null || true)"
    focused_display="$("${YABAI_BIN}" -m query --displays --display 2>/dev/null | "${JQ_BIN}" -r '.index // empty' 2>/dev/null || true)"
    if [[ -n "${target_display}" && "${target_display}" != "${focused_display}" ]]; then
      "${YABAI_BIN}" -m display --focus "${target_display}" >/dev/null 2>&1 || true
    fi
  else
    "${YABAI_BIN}" -m display --focus mouse >/dev/null 2>&1 || true
  fi
fi

if [[ -n "${ITEM_NAME}" ]]; then
  "${SKETCHYBAR_BIN}" --set "${ITEM_NAME}" popup.drawing=toggle
fi
