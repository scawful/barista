#!/bin/bash

# Small, provider-agnostic actions for the optional Task Pulse surface.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
OPEN_BIN="${BARISTA_OPEN_BIN:-/usr/bin/open}"
TASK_SOURCES="${BARISTA_CALENDAR_TASK_SOURCES:-${BARISTA_TASK_SOURCES:-}}"

first_task_source() {
  local source remainder
  source="$TASK_SOURCES"
  if [[ "$source" == *:* ]]; then
    remainder="${source#*:}"
    source="${source%:"$remainder"}"
  fi
  source="${source#"${source%%[![:space:]]*}"}"
  source="${source%"${source##*[![:space:]]}"}"
  if [[ "$source" == \~/* ]]; then
    source="$HOME/${source#\~/}"
  fi
  printf '%s\n' "$source"
}

notify_task_change() {
  "$SKETCHYBAR_BIN" --trigger task_state_changed >/dev/null 2>&1 || true
}

action="${1:-open}"
case "$action" in
  open)
    source_path="$(first_task_source)"
    if [[ -z "$source_path" ]]; then
      echo "task_action: no task source configured" >&2
      exit 1
    fi
    "$OPEN_BIN" "$source_path"
    ;;
  capture)
    shift
    exec "$CONFIG_DIR/scripts/task_capture.sh" "$@"
    ;;
  refresh)
    notify_task_change
    ;;
  *)
    echo "Usage: $0 open|capture|refresh" >&2
    exit 2
    ;;
esac
