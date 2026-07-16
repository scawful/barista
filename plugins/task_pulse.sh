#!/bin/bash

# Refresh the optional Task Pulse chip and its bounded popup rows.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
SNAPSHOT_SCRIPT="${BARISTA_TASK_SNAPSHOT_SCRIPT:-$CONFIG_DIR/scripts/task_snapshot.py}"
FOCUS_SESSION_SCRIPT="${BARISTA_FOCUS_SESSION_SCRIPT:-$CONFIG_DIR/scripts/focus_session.py}"
TASK_PROVIDER="${BARISTA_TASK_PROVIDER:-files}"
TASK_SOURCES="${BARISTA_CALENDAR_TASK_SOURCES:-${BARISTA_TASK_SOURCES:-}}"
SYSHELP_BIN="${BARISTA_SYSHELP_BIN:-syshelp}"
CACHE_DIR="${BARISTA_TASK_CACHE_DIR:-$CONFIG_DIR/cache/task_focus}"
SNAPSHOT_FILE="$CACHE_DIR/summary.json"

mkdir -p "$CACHE_DIR"

snapshot_args=(--provider "$TASK_PROVIDER" --output "$SNAPSHOT_FILE")
if [[ -n "$TASK_SOURCES" ]]; then
  snapshot_args+=(--sources "$TASK_SOURCES")
fi
if [[ "$TASK_PROVIDER" == "syshelp" ]]; then
  snapshot_args+=(--syshelp-bin "$SYSHELP_BIN")
fi

snapshot_error=""
snapshot_failed=0
if ! snapshot_error="$(python3 "$SNAPSHOT_SCRIPT" "${snapshot_args[@]}" 2>&1)"; then
  snapshot_failed=1
fi

if [[ "$snapshot_failed" -eq 1 || -n "$snapshot_error" || ! -s "$SNAPSHOT_FILE" ]]; then
  "$SKETCHYBAR_BIN" \
    --set task_focus label="Tasks !" drawing=on \
    --set task_focus.summary label="Task provider unavailable" drawing=on \
    --set task_focus.focus label="Focus: —" drawing=on \
    --set task_focus.next label="Next: —" drawing=on \
    --set task_focus.waiting label="Waiting: —" drawing=on \
    --set task_focus.blocked label="Blocked: —" drawing=on \
    --set task_focus.timer label="Start 25m Focus" drawing=on
  exit 0
fi

FOCUS_STATUS_JSON=""
if [[ -x "$FOCUS_SESSION_SCRIPT" ]]; then
  FOCUS_STATUS_JSON="$("$FOCUS_SESSION_SCRIPT" status 2>/dev/null || true)"
fi
export BARISTA_FOCUS_STATUS_JSON="$FOCUS_STATUS_JSON"

FIELDS_FILE="$(mktemp "${TMPDIR:-/tmp}/barista-task-pulse.XXXXXX")"
cleanup() {
  rm -f "$FIELDS_FILE"
}
trap cleanup EXIT

python3 - "$SNAPSHOT_FILE" > "$FIELDS_FILE" <<'PY'
import json
import os
import re
import sys


def compact(value, limit=40):
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)] + "…"


def title(snapshot, key):
    task = snapshot.get(key)
    return compact(task.get("title")) if isinstance(task, dict) else ""


with open(sys.argv[1], "r", encoding="utf-8") as handle:
    snapshot = json.load(handle)

counts = snapshot.get("counts") if isinstance(snapshot.get("counts"), dict) else {}
focus = title(snapshot, "focus")
next_task = title(snapshot, "next")
waiting = title(snapshot, "waiting")
blocked = title(snapshot, "blocked")
open_count = int(counts.get("open") or 0)
active_count = int(counts.get("active") or 0)
next_count = int(counts.get("next") or 0)
sources = [source for source in snapshot.get("sources", []) if isinstance(source, dict)]
source_issue_count = sum(1 for source in sources if source.get("error"))
healthy_source_count = sum(
    1 for source in sources
    if source.get("exists", False) and not source.get("error")
)
source_unavailable = bool(sources) and healthy_source_count == 0

if source_unavailable:
    bar_label = "Tasks !"
elif open_count > 0:
    bar_label = str(open_count)
else:
    bar_label = "Clear"

try:
    focus_status = json.loads(os.environ.get("BARISTA_FOCUS_STATUS_JSON") or "{}")
except json.JSONDecodeError:
    focus_status = {}
if focus_status.get("active"):
    timer_label = f"Focus Session: {int(focus_status.get('remaining_minutes') or 0)}m left"
elif focus_status.get("state") == "expired":
    timer_label = "Focus Session complete · start 25m"
else:
    timer_label = "Start 25m Focus"

if source_unavailable:
    summary = "Task source unavailable"
else:
    summary = f"{open_count} open · {active_count} active · {next_count} next"
    if source_issue_count:
        suffix = "issue" if source_issue_count == 1 else "issues"
        summary += f" · {source_issue_count} source {suffix}"

fields = {
    "bar": bar_label,
    "summary": summary,
    "focus": f"Focus: {focus or '—'}",
    "next": f"Next: {next_task or '—'}",
    "waiting": f"Waiting: {waiting or ('—' if source_unavailable else 'Clear')}",
    "blocked": f"Blocked: {blocked or ('—' if source_unavailable else 'Clear')}",
    "timer": timer_label,
}
for key in ("bar", "summary", "focus", "next", "waiting", "blocked", "timer"):
    print(f"{key}\t{fields[key]}")
PY

bar_label="Tasks"
summary_label="Tasks: —"
focus_label="Focus: —"
next_label="Next: —"
waiting_label="Waiting: —"
blocked_label="Blocked: —"
timer_label="Start 25m Focus"
while IFS=$'\t' read -r key value; do
  case "$key" in
    bar) bar_label="$value" ;;
    summary) summary_label="$value" ;;
    focus) focus_label="$value" ;;
    next) next_label="$value" ;;
    waiting) waiting_label="$value" ;;
    blocked) blocked_label="$value" ;;
    timer) timer_label="$value" ;;
  esac
done < "$FIELDS_FILE"

"$SKETCHYBAR_BIN" \
  --set task_focus label="$bar_label" drawing=on \
  --set task_focus.summary label="$summary_label" drawing=on \
  --set task_focus.focus label="$focus_label" drawing=on \
  --set task_focus.next label="$next_label" drawing=on \
  --set task_focus.waiting label="$waiting_label" drawing=on \
  --set task_focus.blocked label="$blocked_label" drawing=on \
  --set task_focus.timer label="$timer_label" drawing=on
