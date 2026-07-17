#!/bin/bash

# Small, provider-agnostic actions for the optional Task Pulse surface.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
OPEN_BIN="${BARISTA_OPEN_BIN:-/usr/bin/open}"
TASK_SOURCES="${BARISTA_CALENDAR_TASK_SOURCES:-${BARISTA_TASK_SOURCES:-}}"
TASK_PROVIDER="${BARISTA_TASK_PROVIDER:-files}"
SYSHELP_BIN="${BARISTA_SYSHELP_BIN:-$(command -v syshelp 2>/dev/null || true)}"
SNAPSHOT_SCRIPT="${BARISTA_TASK_SNAPSHOT_SCRIPT:-$CONFIG_DIR/scripts/task_snapshot.py}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-/usr/bin/osascript}"
SNAPSHOT_FILE=""
FOCUS_FILE=""
RECHECK_SNAPSHOT_FILE=""
RECHECK_FOCUS_FILE=""

cleanup() {
  [[ -z "$SNAPSHOT_FILE" ]] || rm -f -- "$SNAPSHOT_FILE"
  [[ -z "$FOCUS_FILE" ]] || rm -f -- "$FOCUS_FILE"
  [[ -z "$RECHECK_SNAPSHOT_FILE" ]] || rm -f -- "$RECHECK_SNAPSHOT_FILE"
  [[ -z "$RECHECK_FOCUS_FILE" ]] || rm -f -- "$RECHECK_FOCUS_FILE"
}
trap cleanup EXIT

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

write_focus_fields() {
  local snapshot_file="$1"
  local output_file="$2"
  local expected_file="${3:-}"

  python3 - "$snapshot_file" "$expected_file" > "$output_file" <<'PY'
import json
from pathlib import Path
import sys


with open(sys.argv[1], "r", encoding="utf-8") as handle:
    snapshot = json.load(handle)

focus = snapshot.get("focus")
if not isinstance(focus, dict) or not focus.get("open"):
    raise SystemExit("task_action: no open focus task")

focus_id = str(focus.get("id") or "").strip()
title = str(focus.get("title") or "").strip()
section = str(focus.get("section") or "").strip()
if not focus_id or not title or not section or any("\0" in value for value in (focus_id, title, section)):
    raise SystemExit("task_action: focus task is missing a safe id, title, or section")

# syshelp's done query is a case-insensitive substring match within a section.
# Refuse ambiguous snapshots so the exact fresh focus is the only possible row.
tasks = snapshot.get("tasks")
if not isinstance(tasks, list):
    raise SystemExit("task_action: focus snapshot has no task list")
matches = [
    task
    for task in tasks
    if isinstance(task, dict)
    and task.get("open")
    and str(task.get("section") or "").strip().casefold() == section.casefold()
    and title.casefold() in str(task.get("title") or "").strip().casefold()
]
if len(matches) != 1 or matches[0].get("id") != focus_id:
    raise SystemExit("task_action: focus title is ambiguous within its section")

if sys.argv[2]:
    expected_parts = Path(sys.argv[2]).read_bytes().split(b"\0")
    if len(expected_parts) != 4 or expected_parts[-1] != b"":
        raise SystemExit("task_action: original focus identity is invalid")
    expected = tuple(part.decode("utf-8") for part in expected_parts[:3])
    if (focus_id, title, section) != expected:
        raise SystemExit("task_action: focus changed while awaiting confirmation")

sys.stdout.buffer.write(
    focus_id.encode("utf-8")
    + b"\0"
    + title.encode("utf-8")
    + b"\0"
    + section.encode("utf-8")
    + b"\0"
)
PY
}

complete_focus() {
  if [[ "$TASK_PROVIDER" != "syshelp" ]]; then
    echo "task_action: complete-focus requires the syshelp provider" >&2
    return 2
  fi
  if [[ -z "$SYSHELP_BIN" || ! -x "$SYSHELP_BIN" ]]; then
    echo "task_action: syshelp provider is configured but unavailable" >&2
    return 1
  fi
  if [[ ! -f "$SNAPSHOT_SCRIPT" ]]; then
    echo "task_action: task snapshot helper missing: $SNAPSHOT_SCRIPT" >&2
    return 1
  fi
  if [[ ! -x "$OSASCRIPT_BIN" ]]; then
    echo "task_action: confirmation helper unavailable: $OSASCRIPT_BIN" >&2
    return 1
  fi

  SNAPSHOT_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-complete-focus.XXXXXX")"
  FOCUS_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-complete-focus-fields.XXXXXX")"
  python3 "$SNAPSHOT_SCRIPT" \
    --provider syshelp \
    --syshelp-bin "$SYSHELP_BIN" \
    --output "$SNAPSHOT_FILE"
  write_focus_fields "$SNAPSHOT_FILE" "$FOCUS_FILE"

  local _focus_id focus_title focus_section
  exec 3< "$FOCUS_FILE"
  IFS= read -r -d '' _focus_id <&3
  IFS= read -r -d '' focus_title <&3
  IFS= read -r -d '' focus_section <&3
  exec 3<&-

  if ! "$OSASCRIPT_BIN" - "$focus_title" <<'APPLESCRIPT' >/dev/null
on run argv
  set taskTitle to item 1 of argv
  display dialog ("Mark this focus task done?" & return & return & taskTitle) with title "Complete Focus" buttons {"Cancel", "Complete"} default button "Cancel" cancel button "Cancel" with icon note
end run
APPLESCRIPT
  then
    return 0
  fi

  RECHECK_SNAPSHOT_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-complete-focus-recheck.XXXXXX")"
  RECHECK_FOCUS_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-complete-focus-recheck-fields.XXXXXX")"
  python3 "$SNAPSHOT_SCRIPT" \
    --provider syshelp \
    --syshelp-bin "$SYSHELP_BIN" \
    --output "$RECHECK_SNAPSHOT_FILE"
  write_focus_fields "$RECHECK_SNAPSHOT_FILE" "$RECHECK_FOCUS_FILE" "$FOCUS_FILE"

  "$SYSHELP_BIN" plan tasks "done" "$focus_title" "$focus_section"
  notify_task_change
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
  complete-focus)
    complete_focus
    ;;
  refresh)
    notify_task_change
    ;;
  *)
    echo "Usage: $0 open|capture|complete-focus|refresh" >&2
    exit 2
    ;;
esac
