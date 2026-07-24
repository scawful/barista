#!/usr/bin/env bash
set -euo pipefail

# External callers cannot safely cache the per-reload popup topology token.
# Forward through the click script currently installed on the requested item.

ITEM_NAME="${1:-${NAME:-}}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq 2>/dev/null || true)}"

[[ -n "${ITEM_NAME}" ]] || exit 2
[[ -n "${SKETCHYBAR_BIN}" ]] || SKETCHYBAR_BIN="sketchybar"

click_script=""
if [[ "${BARISTA_POPUP_CLICK_FORWARDING:-0}" != "1" \
    && -n "${JQ_BIN}" && -x "${JQ_BIN}" ]]; then
  click_script="$(
    "${SKETCHYBAR_BIN}" --query "${ITEM_NAME}" 2>/dev/null \
      | "${JQ_BIN}" -er '.scripting.click_script | select(type == "string" and length > 0)' \
        2>/dev/null \
      || true
  )"
fi

if [[ -n "${click_script}" ]]; then
  BARISTA_POPUP_CLICK_FORWARDING=1 NAME="${ITEM_NAME}" SENDER=mouse.clicked \
    /bin/sh -c "${click_script}"
else
  "${SKETCHYBAR_BIN}" --set "${ITEM_NAME}" popup.drawing=toggle
fi
