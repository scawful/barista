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
if [[ "${1:-}" == "plan" && "${2:-}" == "tasks" && "${3:-}" == "json" ]]; then
  cat "${BARISTA_TASK_ACTION_FIXTURE:?}"
fi
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

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf 'osascript'
  printf '\t%s' "$@"
  printf '\n'
} >> "${BARISTA_TASK_ACTION_TEST_LOG:?}"
cat >/dev/null
if [[ -n "${BARISTA_TASK_CONFIRM_REPLACEMENT:-}" ]]; then
  cp "${BARISTA_TASK_CONFIRM_REPLACEMENT}" "${BARISTA_TASK_ACTION_FIXTURE:?}"
fi
exit "${BARISTA_TASK_CONFIRM_EXIT:-0}"
EOF
chmod +x "$BIN_DIR/syshelp" "$BIN_DIR/sketchybar" "$BIN_DIR/open" "$BIN_DIR/osascript"

grep -Fq 'default button "Cancel" cancel button "Cancel"' "$ROOT_DIR/scripts/task_action.sh" || {
  echo "FAIL: complete-focus confirmation must default to the non-mutating choice" >&2
  exit 1
}

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

FOCUS_TITLE="Ship exact focus; \$(touch $INJECTION_MARKER)"
FOCUS_FIXTURE="$TMP_DIR/focus.json"
cat > "$FOCUS_FIXTURE" <<EOF
{
  "file": "$TASK_FILE",
  "sections": [
    {
      "name": "Active",
      "tasks": [
        {"line": 4, "state": "ACTIVE", "title": "$FOCUS_TITLE"},
        {"line": 5, "state": "NEXT", "title": "Later task"}
      ]
    }
  ]
}
EOF

: > "$LOG_FILE"
HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_ACTION_FIXTURE="$FOCUS_FIXTURE" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" complete-focus

grep -Fqx $'syshelp\tplan\ttasks\tjson' "$LOG_FILE" || {
  echo "FAIL: complete-focus should resolve a fresh syshelp snapshot" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fqx $'osascript\t-\t'"$FOCUS_TITLE" "$LOG_FILE" || {
  echo "FAIL: complete-focus should confirm the exact fresh focus title" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fqx $'syshelp\tplan\ttasks\tdone\t'"$FOCUS_TITLE"$'\tActive' "$LOG_FILE" || {
  echo "FAIL: complete-focus should pass the exact title and section to syshelp" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fqx $'sketchybar\t--trigger\ttask_state_changed' "$LOG_FILE" || {
  echo "FAIL: complete-focus should refresh task surfaces after success" >&2
  exit 1
}
[[ ! -e "$INJECTION_MARKER" ]] || {
  echo "FAIL: complete-focus title was evaluated as shell input" >&2
  exit 1
}

: > "$LOG_FILE"
BARISTA_TASK_CONFIRM_EXIT=1 \
  HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_ACTION_FIXTURE="$FOCUS_FIXTURE" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" complete-focus

if grep -Fq $'syshelp\tplan\ttasks\tdone\t' "$LOG_FILE"; then
  echo "FAIL: cancelled complete-focus should not mutate the task provider" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi
if grep -Fq $'sketchybar\t--trigger\ttask_state_changed' "$LOG_FILE"; then
  echo "FAIL: cancelled complete-focus should not emit a task change" >&2
  exit 1
fi

: > "$LOG_FILE"
if HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=files \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_ACTION_FIXTURE="$FOCUS_FIXTURE" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" complete-focus 2>/dev/null; then
  echo "FAIL: files provider must reject complete-focus" >&2
  exit 1
fi
[[ ! -s "$LOG_FILE" ]] || {
  echo "FAIL: files provider should fail before snapshot, confirmation, or mutation" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

AMBIGUOUS_FIXTURE="$TMP_DIR/ambiguous-focus.json"
cat > "$AMBIGUOUS_FIXTURE" <<EOF
{
  "file": "$TASK_FILE",
  "sections": [
    {
      "name": "Active",
      "tasks": [
        {"line": 4, "state": "NEXT", "title": "$FOCUS_TITLE plus follow-up"},
        {"line": 5, "state": "ACTIVE", "title": "$FOCUS_TITLE"}
      ]
    }
  ]
}
EOF

: > "$LOG_FILE"
if HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_ACTION_FIXTURE="$AMBIGUOUS_FIXTURE" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" complete-focus 2>/dev/null; then
  echo "FAIL: ambiguous syshelp substring matches must fail closed" >&2
  exit 1
fi
if grep -Eq $'^(osascript|syshelp\tplan\ttasks\tdone|sketchybar\t--trigger)' "$LOG_FILE"; then
  echo "FAIL: ambiguous focus must fail before confirmation, mutation, or refresh" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

TOCTOU_REPLACEMENT="$TMP_DIR/focus-changed-after-confirmation.json"
cat > "$TOCTOU_REPLACEMENT" <<EOF
{
  "file": "$TASK_FILE",
  "sections": [
    {
      "name": "Active",
      "tasks": [
        {"line": 3, "state": "NEXT", "title": "$FOCUS_TITLE plus follow-up"},
        {"line": 4, "state": "ACTIVE", "title": "$FOCUS_TITLE"}
      ]
    }
  ]
}
EOF
cp "$FOCUS_FIXTURE" "$TMP_DIR/toctou-live.json"

: > "$LOG_FILE"
if HOME="$TMP_DIR/home" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TASK_PROVIDER=syshelp \
  BARISTA_SYSHELP_BIN="$BIN_DIR/syshelp" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TASK_CONFIRM_REPLACEMENT="$TOCTOU_REPLACEMENT" \
  BARISTA_TASK_ACTION_FIXTURE="$TMP_DIR/toctou-live.json" \
  BARISTA_TASK_ACTION_TEST_LOG="$LOG_FILE" \
  "$ROOT_DIR/scripts/task_action.sh" complete-focus 2>/dev/null; then
  echo "FAIL: focus changes after confirmation must fail closed" >&2
  exit 1
fi
[[ "$(grep -Fc $'syshelp\tplan\ttasks\tjson' "$LOG_FILE")" == "2" ]] || {
  echo "FAIL: complete-focus should take a second fresh snapshot after confirmation" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
if grep -Eq $'^(syshelp\tplan\ttasks\tdone|sketchybar\t--trigger)' "$LOG_FILE"; then
  echo "FAIL: post-confirmation focus drift must not mutate or emit a task change" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

printf 'test_task_actions.sh: ok\n'
