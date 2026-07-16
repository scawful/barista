#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/actions.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$TMP_DIR/tasks"
: > "$LOG_FILE"

cat > "$BIN_DIR/syshelp" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'syshelp'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_ACTION_TEST_LOG:?}"
EOF

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'sketchybar'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_ACTION_TEST_LOG:?}"
EOF

cat > "$BIN_DIR/open" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'open'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_ACTION_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/syshelp" "$BIN_DIR/sketchybar" "$BIN_DIR/open"

INJECTION_MARKER="$TMP_DIR/should-not-exist"
CAPTURE_TITLE=$'Review quoted input; $(touch '"$INJECTION_MARKER"$')\n  follow-up\titem'
NORMALIZED_TITLE="Review quoted input; \$(touch $INJECTION_MARKER) follow-up item"

HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_CAPTURE_TITLE="$CAPTURE_TITLE" \
  BARISTA_CAPTURE_SECTION=$'Inbox\nQueue' \
  BARISTA_CAPTURE_STATE=next \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_capture.sh"

grep -Fqx $'syshelp\tplan\ttasks\tadd\t'"$NORMALIZED_TITLE"$'\t--section\tInbox Queue\t--state\tNEXT' "$LOG_FILE" || {
  echo "FAIL: capture should normalize control whitespace and preserve one literal title argument" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fqx $'sketchybar\t--trigger\ttask_state_changed' "$LOG_FILE" || {
  echo "FAIL: capture should trigger a task refresh" >&2
  exit 1
}
[[ ! -e "$INJECTION_MARKER" ]] || {
  echo "FAIL: capture title was evaluated as shell input" >&2
  exit 1
}

: > "$LOG_FILE"
TASK_FILE="$TMP_DIR/tasks/active board.md"
: > "$TASK_FILE"
HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_OPEN_BIN="$BIN_DIR/open" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE:$TMP_DIR/tasks/other.org" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" open

grep -Fqx $'open\t'"$TASK_FILE" "$LOG_FILE" || {
  echo "FAIL: open should use the first configured task source literally" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

: > "$LOG_FILE"
HOME="$TMP_DIR/home" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_CAPTURE_TITLE='' \
  BARISTA_OPEN_BIN="$BIN_DIR/open" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_capture.sh"

grep -Fqx $'open\t'"$TASK_FILE" "$LOG_FILE" || {
  echo "FAIL: files capture should open the board without requiring a title" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

printf 'test_task_actions.sh: ok\n'
