#!/bin/bash

# Capture a task through an explicitly configured provider.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
PROVIDER="${BARISTA_TASK_PROVIDER:-files}"
SECTION="${BARISTA_CAPTURE_SECTION:-Active}"
STATE="${BARISTA_CAPTURE_STATE:-TODO}"
SYSHELP_BIN="${BARISTA_SYSHELP_BIN:-$(command -v syshelp 2>/dev/null || true)}"

case "$PROVIDER" in
  files)
    # Barista deliberately does not invent file mutation rules. Open the
    # configured board so the owner/provider remains the source of truth.
    exec "$CONFIG_DIR/scripts/task_action.sh" open
    ;;
  syshelp)
    ;;
  *)
    echo "task_capture: unsupported provider: $PROVIDER" >&2
    exit 2
    ;;
esac

prompt_title() {
  if [[ -n "${BARISTA_CAPTURE_TITLE+x}" ]]; then
    printf '%s\n' "$BARISTA_CAPTURE_TITLE"
    return 0
  fi
  if (( $# > 0 )); then
    printf '%s\n' "$*"
    return 0
  fi
  /usr/bin/osascript -e 'text returned of (display dialog "Capture task" default answer "" with title "Barista Task Pulse" buttons {"Cancel", "Add"} default button "Add" cancel button "Cancel")' 2>/dev/null
}

title="$(prompt_title "$@")" || exit 0

normalize_inline() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  while [[ "$value" == *"  "* ]]; do
    value="${value//  / }"
  done
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

title="$(normalize_inline "$title")"
[[ -n "$title" ]] || exit 0
title="${title:0:240}"

SECTION="$(normalize_inline "$SECTION")"
SECTION="${SECTION:0:80}"
[[ -n "$SECTION" ]] || SECTION="Active"
STATE="$(normalize_inline "$STATE")"
STATE="$(printf '%s' "$STATE" | tr '[:lower:]' '[:upper:]')"
case "$STATE" in
  TODO|NEXT|ACTIVE|WAITING|BLOCKED) ;;
  *)
    echo "task_capture: unsupported capture state: $STATE" >&2
    exit 2
    ;;
esac

if [[ -z "$SYSHELP_BIN" || ! -x "$SYSHELP_BIN" ]]; then
  echo "task_capture: syshelp provider is configured but unavailable" >&2
  exit 1
fi
"$SYSHELP_BIN" plan tasks add "$title" --section "$SECTION" --state "$STATE"

"$SKETCHYBAR_BIN" --trigger task_state_changed >/dev/null 2>&1 || true
