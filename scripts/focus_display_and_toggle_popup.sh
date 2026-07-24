#!/usr/bin/env bash
set -euo pipefail

# Focus the display under the mouse before toggling a popup.
# This prevents cross-monitor popup mismatches when display focus lags.

ITEM_NAME="${1:-${NAME:-}}"
CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
POPUP_MANAGER_BIN="${BARISTA_POPUP_MANAGER_BIN:-}"
POPUP_PROTOCOL_PROBE="${CONFIG_DIR}/scripts/popup_switch_protocol_probe.pl"
POPUP_CLICK_INVOKER="${CONFIG_DIR}/scripts/invoke_popup_click.sh"

popup_manager_compatible() {
  [[ -x "$1" && -r "${POPUP_PROTOCOL_PROBE}" ]] || return 1
  /usr/bin/perl "${POPUP_PROTOCOL_PROBE}" "$1"
}

if [[ -n "${BARISTA_POPUP_TOPOLOGY_TOKEN:-}" ]]; then
  if [[ -n "${POPUP_MANAGER_BIN}" ]] && ! popup_manager_compatible "${POPUP_MANAGER_BIN}"; then
    POPUP_MANAGER_BIN=""
  fi

  if [[ -z "${POPUP_MANAGER_BIN}" ]]; then
    for candidate in \
      "${CONFIG_DIR}/build/bin/popup_switch" \
      "${CONFIG_DIR}/bin/popup_switch" \
      "${CONFIG_DIR}/plugins/popup_manager.sh"; do
      if popup_manager_compatible "${candidate}"; then
        POPUP_MANAGER_BIN="${candidate}"
        break
      fi
    done
  fi
else
  # Resolve the current token through the live item's configured click instead
  # of trusting a potentially stale manifest generation.
  POPUP_MANAGER_BIN=""
fi

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
  if [[ -n "${POPUP_MANAGER_BIN}" ]]; then
    BARISTA_SKETCHYBAR_BIN="${SKETCHYBAR_BIN}" \
      BARISTA_POPUP_TOPOLOGY_TOKEN="${BARISTA_POPUP_TOPOLOGY_TOKEN}" \
      "${POPUP_MANAGER_BIN}" switch "${ITEM_NAME}"
  elif [[ -r "${POPUP_CLICK_INVOKER}" ]]; then
    SKETCHYBAR_BIN="${SKETCHYBAR_BIN}" /bin/bash "${POPUP_CLICK_INVOKER}" "${ITEM_NAME}"
  else
    "${SKETCHYBAR_BIN}" --set "${ITEM_NAME}" popup.drawing=toggle
  fi
fi
