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
OWNER_SCRIPT="$TMP_DIR/current-clock-owner.sh"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$CONFIG_DIR/scripts" "$BIN_DIR"

cp "$ROOT_DIR/scripts/invoke_popup_click.sh" "$CONFIG_DIR/scripts/invoke_popup_click.sh"

cat > "$OWNER_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'owner\tname=%s\tsender=%s\tforwarding=%s\tsources=%s\n' \
  "${NAME-}" "${SENDER-}" "${BARISTA_POPUP_CLICK_FORWARDING-}" \
  "${BARISTA_CALENDAR_TASK_SOURCES-<unset>}" >> "${BARISTA_TASK_FOCUS_TEST_LOG:?}"
EOF
chmod +x "$OWNER_SCRIPT"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'sketchybar'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_FOCUS_TEST_LOG:?}"
if [[ "${1:-}" == "--query" ]]; then
  if [[ "${BARISTA_TASK_FOCUS_QUERY_FAIL:-0}" == "1" ]]; then
    exit 1
  fi
  jq -n --arg script "${BARISTA_TASK_FOCUS_CURRENT_CLICK:?}" \
    '{scripting: {click_script: $script}}'
fi
EOF
chmod +x "$BIN_DIR/sketchybar"

TASK_SOURCES="$TMP_DIR/tasks/active board.md:$TMP_DIR/tasks/next;board [draft].org:\$(touch $TMP_DIR/should-not-exist)"

HOME="$TEST_HOME" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  BARISTA_CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_FOCUS_CURRENT_CLICK="$OWNER_SCRIPT" \
  BARISTA_CALENDAR_TASK_SOURCES="$TASK_SOURCES" \
  BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
  "$SCRIPT"

{
  printf 'sketchybar\t--query\tclock\n'
  printf 'owner\tname=clock\tsender=mouse.clicked\tforwarding=1\tsources=%s\n' "$TASK_SOURCES"
} > "$EXPECTED_FILE"

cmp -s "$EXPECTED_FILE" "$LOG_FILE" || {
  echo "FAIL: task focus should forward through the clock's live click owner" >&2
  diff -u "$EXPECTED_FILE" "$LOG_FILE" >&2 || true
  exit 1
}

if [ -e "$TMP_DIR/should-not-exist" ]; then
  echo "FAIL: task source text was evaluated as shell input" >&2
  exit 1
fi

: > "$LOG_FILE"
HOME="$TEST_HOME" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  BARISTA_CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_FOCUS_CURRENT_CLICK="$OWNER_SCRIPT" \
  BARISTA_TASK_FOCUS_QUERY_FAIL=1 \
  BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
  "$SCRIPT"
{
  printf 'sketchybar\t--query\tclock\n'
  printf 'sketchybar\t--set\tclock\tpopup.drawing=toggle\n'
} > "$EXPECTED_FILE"
cmp -s "$EXPECTED_FILE" "$LOG_FILE" || {
  echo "FAIL: task focus should retain the target-only popup fallback" >&2
  diff -u "$EXPECTED_FILE" "$LOG_FILE" >&2 || true
  exit 1
}

STANDALONE_CONFIG="$TMP_DIR/standalone-config"
mkdir -p "$STANDALONE_CONFIG/scripts"
cp "$SCRIPT" "$STANDALONE_CONFIG/scripts/task_focus.sh"
cp "$CONFIG_DIR/scripts/invoke_popup_click.sh" "$STANDALONE_CONFIG/scripts/"
: >"$LOG_FILE"
env -u BARISTA_CONFIG_DIR \
  HOME="$TEST_HOME" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_FOCUS_CURRENT_CLICK="$OWNER_SCRIPT" \
  BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
  "$STANDALONE_CONFIG/scripts/task_focus.sh"
grep -Fq $'owner\tname=clock\tsender=mouse.clicked\tforwarding=1' "$LOG_FILE" || {
  echo "FAIL: task focus did not use its own non-default install root" >&2
  exit 1
}

: > "$LOG_FILE"
MISSING_HELPER="$TMP_DIR/missing-popup-click.sh"
set +e
missing_output="$(
  HOME="$TEST_HOME" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    BARISTA_CONFIG_DIR="$CONFIG_DIR" \
    BARISTA_POPUP_CLICK_SCRIPT="$MISSING_HELPER" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_TASK_FOCUS_TEST_LOG="$LOG_FILE" \
    "$SCRIPT" 2>&1
)"
missing_status=$?
set -e
[[ "$missing_status" -eq 1 ]] || {
  echo "FAIL: task focus should fail when its click helper is unavailable" >&2
  exit 1
}
[[ "$missing_output" == "task_focus: popup click helper missing: $MISSING_HELPER" ]] || {
  echo "FAIL: task focus missing-helper diagnostic changed" >&2
  printf '%s\n' "$missing_output" >&2
  exit 1
}
[[ ! -s "$LOG_FILE" ]] || {
  echo "FAIL: task focus should not call SketchyBar without its click helper" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

printf 'test_task_focus.sh: ok\n'
