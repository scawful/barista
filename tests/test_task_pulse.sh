#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/task_pulse.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
TASK_FILE="$TMP_DIR/active board.md"
LOG_FILE="$TMP_DIR/sketchybar.log"
FOCUS_STATE_FILE="$TMP_DIR/focus-state.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
cat > "$TASK_FILE" <<'EOF'
# Active Tasks

## Active
- [ ] Current focus item with enough detail for the popup menu
- [ ] [NEXT] Ship Task Pulse

## Waiting
- [ ] Await design review

## Blocked
- [ ] Need test credential
EOF

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'call'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_PULSE_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/sketchybar"

BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_PULSE_TEST_LOG="$LOG_FILE" \
  BARISTA_TASK_CACHE_DIR="$TMP_DIR/cache" \
  BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE:$TMP_DIR/missing.md" \
  "$SCRIPT"

[[ "$(wc -l < "$LOG_FILE" | tr -d ' ')" == "1" ]] || {
  echo "FAIL: Task Pulse should batch updates into one SketchyBar call" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus\tlabel=4\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should keep the closed chip to the open count" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.focus\tlabel=Focus: Current focus item with enough detail f…\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should keep task detail in a bounded popup row" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.timer\tlabel=Start 25m Focus\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should expose one menu-only focus-session action" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.summary\tlabel=4 open · 1 active · 1 next · 1 source issue\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should render normalized counts and partial source degradation" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.waiting\tlabel=Waiting: Await design review\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should keep waiting distinct" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.blocked\tlabel=Blocked: Need test credential\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should keep blocked distinct" >&2
  exit 1
}

jq -e '.focus.title == "Current focus item with enough detail for the popup menu" and .next.title == "Ship Task Pulse"' \
  "$TMP_DIR/cache/summary.json" >/dev/null

BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  "$ROOT_DIR/scripts/focus_session.py" start 25 >/dev/null
: > "$LOG_FILE"
BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_PULSE_TEST_LOG="$LOG_FILE" \
  BARISTA_TASK_CACHE_DIR="$TMP_DIR/cache" \
  BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE" \
  "$SCRIPT"

grep -Eq -- $'--set\ttask_focus.timer\tlabel=Focus Session: (24|25)m left\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should render the active focus-session deadline" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  "$ROOT_DIR/scripts/focus_session.py" stop >/dev/null

: > "$LOG_FILE"
cat > "$TASK_FILE" <<'EOF'
# Active Tasks

## Complete
- [x] Finished task
EOF

BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_PULSE_TEST_LOG="$LOG_FILE" \
  BARISTA_TASK_CACHE_DIR="$TMP_DIR/clear-cache" \
  BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_FILE" \
  "$SCRIPT"

grep -Fq -- $'--set\ttask_focus\tlabel=Clear\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should preserve the clear chip state" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.focus\tlabel=Focus: —\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should clear stale popup focus details" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

: > "$LOG_FILE"
BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_PULSE_TEST_LOG="$LOG_FILE" \
  BARISTA_TASK_CACHE_DIR="$TMP_DIR/error-cache" \
  BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_SYSHELP_BIN="$TMP_DIR/missing-syshelp" \
  "$SCRIPT"

grep -Fq -- $'--set\ttask_focus\tlabel=Tasks !\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should expose provider failure without stale task data" >&2
  exit 1
}

: > "$LOG_FILE"
BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_PULSE_TEST_LOG="$LOG_FILE" \
  BARISTA_TASK_CACHE_DIR="$TMP_DIR/missing-cache" \
  BARISTA_FOCUS_STATE_FILE="$FOCUS_STATE_FILE" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_CALENDAR_TASK_SOURCES="$TMP_DIR/missing.md" \
  "$SCRIPT"

grep -Fq -- $'--set\ttask_focus\tlabel=Tasks !\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: an unavailable configured board must not render as Clear" >&2
  exit 1
}
grep -Fq -- $'--set\ttask_focus.summary\tlabel=Task source unavailable\tdrawing=on' "$LOG_FILE" || {
  echo "FAIL: Task Pulse should explain unavailable sources in its popup" >&2
  exit 1
}

printf 'test_task_pulse.sh: ok\n'
