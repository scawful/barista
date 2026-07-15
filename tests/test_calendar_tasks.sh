#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/calendar.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
TASK_FILE="$TMP_DIR/active.md"
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
EOF

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
LOG_FILE="${BARISTA_TEST_SKETCHYBAR_LOG:?}"
if [ "${1:-}" = "--set" ]; then
  item="${2:-}"
  shift 2
  label=""
  for arg in "$@"; do
    case "$arg" in
      label=*) label="${arg#label=}" ;;
    esac
  done
  printf '%s\t%s\n' "$item" "$label" >> "$LOG_FILE"
fi
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE" \
  "$SCRIPT"

grep -Fq $'clock.calendar.tasks.today\t󰄱 Today: Tune the menu popups' "$LOG_FILE" || {
  echo "FAIL: calendar should surface Today task summary" >&2
  exit 1
}
grep -Fq $'clock.calendar.tasks.next\t󰒭 Next: Revoke the exposed credenti…' "$LOG_FILE" || {
  echo "FAIL: explicit NEXT state should outrank active-task overflow" >&2
  exit 1
}
grep -Fq $'clock.calendar.tasks.blocked\t󰅖 Blocked: Finish old docs cleanup' "$LOG_FILE" || {
  echo "FAIL: calendar should surface Blocked task summary" >&2
  exit 1
}

cat > "$TASK_FILE" <<'EOF'
# Active Tasks

## Active
- [ ] Tune the menu popups
- [ ] Consolidate src app launchers
EOF
: > "$LOG_FILE"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE" \
  "$SCRIPT"

grep -Fq $'clock.calendar.tasks.next\t󰒭 Next: Consolidate src app launche…' "$LOG_FILE" || {
  echo "FAIL: active-task overflow should remain the Next fallback" >&2
  exit 1
}

printf 'test_calendar_tasks.sh: ok\n'
