#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/task_focus.sh"
TMP_DIR="$(mktemp -d)"
TEST_HOME="$TMP_DIR/home"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/task_focus.log"
EXPECTED_FILE="$TMP_DIR/expected.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$CONFIG_DIR/plugins" "$BIN_DIR"

cat > "$CONFIG_DIR/plugins/calendar.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'calendar\targc=%s\tsources=%s\n' \
  "$#" "${BARISTA_CALENDAR_TASK_SOURCES-<unset>}" >> "${BARISTA_TASK_FOCUS_TEST_LOG:?}"
EOF
chmod +x "$CONFIG_DIR/plugins/calendar.sh"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'sketchybar'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_FOCUS_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/sketchybar"

TASK_SOURCES="$TMP_DIR/tasks/active board.md:$TMP_DIR/tasks/next;board [draft].org:\$(touch $TMP_DIR/should-not-exist)"

HOME="$TEST_HOME" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  BARISTA_CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_SOURCES" \
  BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
  "$SCRIPT"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  grep -Fq $'calendar\targc=0' "$LOG_FILE" 2>/dev/null && break
  sleep 0.05
done

{
  printf 'sketchybar\t--trigger\tmouse.exited.global\n'
  printf 'sketchybar\t--set\tclock\tpopup.drawing=on\n'
  printf 'calendar\targc=0\tsources=%s\n' "$TASK_SOURCES"
} > "$EXPECTED_FILE"

cmp -s "$EXPECTED_FILE" "$LOG_FILE" || {
  echo "FAIL: task focus command sequence or arguments changed" >&2
  diff -u "$EXPECTED_FILE" "$LOG_FILE" >&2 || true
  exit 1
}

if [ -e "$TMP_DIR/should-not-exist" ]; then
  echo "FAIL: task source text was evaluated as shell input" >&2
  exit 1
fi

STANDALONE_CONFIG="$TMP_DIR/standalone-config"
mkdir -p "$STANDALONE_CONFIG/scripts" "$STANDALONE_CONFIG/plugins"
cp "$SCRIPT" "$STANDALONE_CONFIG/scripts/task_focus.sh"
cp "$CONFIG_DIR/plugins/calendar.sh" "$STANDALONE_CONFIG/plugins/calendar.sh"
: >"$LOG_FILE"
env -u BARISTA_CONFIG_DIR \
  HOME="$TEST_HOME" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
  "$STANDALONE_CONFIG/scripts/task_focus.sh"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  grep -Fq $'calendar\targc=0' "$LOG_FILE" 2>/dev/null && break
  sleep 0.05
done
grep -Fq $'calendar\targc=0' "$LOG_FILE" || {
  echo "FAIL: task focus did not use its own non-default install root" >&2
  exit 1
}

printf 'test_task_focus.sh: ok\n'
