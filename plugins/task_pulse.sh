#!/bin/bash

# Refresh the optional Task Pulse chip and its bounded popup rows.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
SNAPSHOT_SCRIPT="${BARISTA_TASK_SNAPSHOT_SCRIPT:-$CONFIG_DIR/scripts/task_snapshot.py}"
FOCUS_SESSION_OVERRIDE="${BARISTA_FOCUS_SESSION_SCRIPT:-}"
FOCUS_SESSION_SCRIPT="${BARISTA_FOCUS_SESSION_SCRIPT:-$CONFIG_DIR/scripts/focus_session.py}"
FOCUS_STATE_FILE="${BARISTA_FOCUS_STATE_FILE:-$CONFIG_DIR/cache/focus_session/state.json}"
TASK_PROVIDER="${BARISTA_TASK_PROVIDER:-files}"
TASK_SOURCES="${BARISTA_CALENDAR_TASK_SOURCES:-${BARISTA_TASK_SOURCES:-}}"
SYSHELP_BIN="${BARISTA_SYSHELP_BIN:-syshelp}"
CACHE_DIR="${BARISTA_TASK_CACHE_DIR:-$CONFIG_DIR/cache/task_focus}"
SNAPSHOT_FILE="$CACHE_DIR/summary.json"

mkdir -p "$CACHE_DIR"

snapshot_args=(
  --provider "$TASK_PROVIDER"
  --output "$SNAPSHOT_FILE"
  --barista-fields
  --focus-state-file "$FOCUS_STATE_FILE"
)
if [[ -n "$FOCUS_SESSION_OVERRIDE" ]]; then
  focus_status_json=""
  if [[ -x "$FOCUS_SESSION_SCRIPT" ]]; then
    focus_status_json="$("$FOCUS_SESSION_SCRIPT" status 2>/dev/null || true)"
  fi
  snapshot_args+=(--focus-status-json "$focus_status_json")
else
  snapshot_args+=(--focus-session-script "$FOCUS_SESSION_SCRIPT")
fi
if [[ -n "$TASK_SOURCES" ]]; then
  snapshot_args+=(--sources "$TASK_SOURCES")
fi
if [[ "$TASK_PROVIDER" == "syshelp" ]]; then
  snapshot_args+=(--syshelp-bin "$SYSHELP_BIN")
fi

render_fields=""
snapshot_failed=0
if ! render_fields="$(python3 "$SNAPSHOT_SCRIPT" "${snapshot_args[@]}" 2>&1)"; then
  snapshot_failed=1
fi

render_unavailable() {
  "$SKETCHYBAR_BIN" \
    --set task_focus label="Tasks !" drawing=on \
    --set task_focus.summary label="Task provider unavailable" drawing=on \
    --set task_focus.focus label="Focus: —" drawing=on \
    --set task_focus.next label="Next: —" drawing=on \
    --set task_focus.waiting label="Waiting: —" drawing=on \
    --set task_focus.blocked label="Blocked: —" drawing=on \
    --set task_focus.timer label="Start 25m Focus" drawing=on
}

if [[ "$snapshot_failed" -eq 1 || -z "$render_fields" || ! -s "$SNAPSHOT_FILE" ]]; then
  render_unavailable
  exit 0
fi

bar_label="Tasks"
summary_label="Tasks: —"
focus_label="Focus: —"
next_label="Next: —"
waiting_label="Waiting: —"
blocked_label="Blocked: —"
timer_label="Start 25m Focus"
field_mask=0
field_invalid=0
while IFS= read -r line; do
  if [[ "$line" != *$'\t'* ]]; then
    field_invalid=1
    continue
  fi
  key="${line%%$'\t'*}"
  value="${line#*$'\t'}"
  case "$key" in
    bar)
      ((field_mask & 1)) && field_invalid=1
      bar_label="$value"
      field_mask=$((field_mask | 1))
      ;;
    summary)
      ((field_mask & 2)) && field_invalid=1
      summary_label="$value"
      field_mask=$((field_mask | 2))
      ;;
    focus)
      ((field_mask & 4)) && field_invalid=1
      focus_label="$value"
      field_mask=$((field_mask | 4))
      ;;
    next)
      ((field_mask & 8)) && field_invalid=1
      next_label="$value"
      field_mask=$((field_mask | 8))
      ;;
    waiting)
      ((field_mask & 16)) && field_invalid=1
      waiting_label="$value"
      field_mask=$((field_mask | 16))
      ;;
    blocked)
      ((field_mask & 32)) && field_invalid=1
      blocked_label="$value"
      field_mask=$((field_mask | 32))
      ;;
    timer)
      ((field_mask & 64)) && field_invalid=1
      timer_label="$value"
      field_mask=$((field_mask | 64))
      ;;
    *) field_invalid=1 ;;
  esac
done <<< "$render_fields"

if [[ "$field_invalid" -eq 1 || "$field_mask" -ne 127 ]]; then
  render_unavailable
  exit 0
fi

"$SKETCHYBAR_BIN" \
  --set task_focus label="$bar_label" drawing=on \
  --set task_focus.summary label="$summary_label" drawing=on \
  --set task_focus.focus label="$focus_label" drawing=on \
  --set task_focus.next label="$next_label" drawing=on \
  --set task_focus.waiting label="$waiting_label" drawing=on \
  --set task_focus.blocked label="$blocked_label" drawing=on \
  --set task_focus.timer label="$timer_label" drawing=on
