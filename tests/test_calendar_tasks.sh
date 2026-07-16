#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/calendar.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
TASK_FILE="$TMP_DIR/active.md"
MEETING_CACHE="$TMP_DIR/events.tsv"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
cat > "$TASK_FILE" <<'EOF'
# Active Tasks

## Active
- [ ] Tune the menu popups
- [ ] Consolidate src app launchers
- [ ] [NEXT] Revoke the exposed credential
- [x] Ignore completed work

## Waiting
- [ ] Finish old docs cleanup

## Blocked
- [ ] Need OAuth credentials
EOF

TOMORROW="$(python3 - <<'PY'
import datetime
print((datetime.date.today() + datetime.timedelta(days=1)).isoformat())
PY
)"
printf 'start_date\tstart_time\ttitle\tlocation\tdescription\tcalendar\n' > "$MEETING_CACHE"
printf '%s\t09:30\tDesign Review\tPrivate\tHidden details\tWork\n' "$TOMORROW" >> "$MEETING_CACHE"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
LOG_FILE="${BARISTA_TEST_SKETCHYBAR_LOG:?}"
CALL_FILE="${BARISTA_TEST_SKETCHYBAR_CALLS:?}"
printf 'call\n' >> "$CALL_FILE"
while [ "$#" -gt 0 ]; do
  if [ "$1" != "--set" ]; then
    shift
    continue
  fi
  item="${2:-}"
  shift 2
  label=""
  while [ "$#" -gt 0 ] && [ "$1" != "--set" ]; do
    case "$1" in label=*) label="${1#label=}" ;; esac
    shift
  done
  printf '%s\t%s\n' "$item" "$label" >> "$LOG_FILE"
done
EOF
chmod +x "$BIN_DIR/sketchybar"
: > "$TMP_DIR/sketchybar.calls"

run_calendar() {
  local meeting_cache="${1:-}"
  local meeting_max_age="${2:-}"
  local task_sources="${3:-$TASK_FILE}"
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
    BARISTA_TEST_SKETCHYBAR_CALLS="$TMP_DIR/sketchybar.calls" \
    BARISTA_TASK_CACHE_DIR="$TMP_DIR/cache" \
    BARISTA_CALENDAR_MEETING_CACHE="$meeting_cache" \
    BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS="$meeting_max_age" \
    BARISTA_CALENDAR_TASK_SOURCES="$task_sources" \
    "$SCRIPT"
}

run_calendar "$MEETING_CACHE"

grep -Fq $'clock.calendar.tasks.today\t󰄱 Focus: Tune the menu popups' "$LOG_FILE" || {
  echo "FAIL: calendar should surface the normalized Focus task" >&2
  exit 1
}
grep -Fq $'clock.calendar.meeting.next\tCached: Tomorrow 9:30 AM · Design Review' "$LOG_FILE" || {
  echo "FAIL: calendar should render one bounded cached meeting without private details" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
if grep -Fq 'Private' "$LOG_FILE" || grep -Fq 'Hidden details' "$LOG_FILE" || grep -Fq 'Work' "$LOG_FILE"; then
  echo "FAIL: cached meeting row should expose only time and title" >&2
  exit 1
fi
grep -Fq $'clock.calendar.tasks.next\t󰒭 Next: Revoke the exposed credenti…' "$LOG_FILE" || {
  echo "FAIL: calendar should surface the explicit NEXT task" >&2
  exit 1
}
grep -Fq $'clock.calendar.tasks.waiting\t󰔟 Waiting: Finish old docs cleanup' "$LOG_FILE" || {
  echo "FAIL: calendar should keep Waiting distinct" >&2
  exit 1
}
grep -Fq $'clock.calendar.tasks.blocked\t󰅖 Blocked: Need OAuth credentials' "$LOG_FILE" || {
  echo "FAIL: calendar should keep Blocked distinct" >&2
  exit 1
}
[[ "$(wc -l < "$TMP_DIR/sketchybar.calls" | tr -d ' ')" == "1" ]] || {
  echo "FAIL: calendar should batch all rows into one SketchyBar call" >&2
  exit 1
}

INVALID_MEETING_CACHE="$TMP_DIR/events-invalid-time.tsv"
printf 'start_date\tstart_time\ttitle\n' >"$INVALID_MEETING_CACHE"
printf '%s\tnot-a-time\tMalformed meeting\n' "$TOMORROW" >>"$INVALID_MEETING_CACHE"
: >"$LOG_FILE"
: >"$TMP_DIR/sketchybar.calls"
run_calendar "$INVALID_MEETING_CACHE"
grep -Fqx $'clock.calendar.meeting.next\t' "$LOG_FILE" || {
  echo "FAIL: calendar should reject a nonempty malformed meeting time" >&2
  exit 1
}

python3 - "$MEETING_CACHE" <<'PY'
import os
import sys
import time

stale_time = time.time() - (25 * 60 * 60)
os.utime(sys.argv[1], (stale_time, stale_time))
PY
: > "$LOG_FILE"
: > "$TMP_DIR/sketchybar.calls"
run_calendar "$MEETING_CACHE"
grep -Fqx $'clock.calendar.meeting.next\t' "$LOG_FILE" || {
  echo "FAIL: calendar should hide a meeting cache older than the default 24 hours" >&2
  exit 1
}

: > "$LOG_FILE"
: > "$TMP_DIR/sketchybar.calls"
run_calendar "" "" "$TMP_DIR/missing.md"
grep -Fq $'clock.calendar.tasks.today\t󰄱 Focus: Task source unavailable' "$LOG_FILE" || {
  echo "FAIL: unavailable task sources must not render as an empty healthy board" >&2
  exit 1
}

: > "$LOG_FILE"
: > "$TMP_DIR/sketchybar.calls"
run_calendar "$MEETING_CACHE" 172800
grep -Fq $'clock.calendar.meeting.next\tCached: Tomorrow 9:30 AM · Design Review' "$LOG_FILE" || {
  echo "FAIL: calendar should honor a configured meeting cache freshness limit" >&2
  exit 1
}

cat > "$TASK_FILE" <<'EOF'
# Active Tasks

## Active
- [ ] Tune the menu popups
- [ ] Consolidate src app launchers
EOF
: > "$LOG_FILE"
: > "$TMP_DIR/sketchybar.calls"

run_calendar

grep -Fq $'clock.calendar.tasks.next\t󰒭 Next: —' "$LOG_FILE" || {
  echo "FAIL: active overflow must not be mislabeled as Next" >&2
  exit 1
}
grep -Fqx $'clock.calendar.meeting.next\t' "$LOG_FILE" || {
  echo "FAIL: calendar should hide the cached meeting row when no path is configured" >&2
  exit 1
}

printf 'test_calendar_tasks.sh: ok\n'
