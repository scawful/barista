#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/yabai_control.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/yabai.log"
STATE_FILE="$TMP_DIR/window_state"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

{
  printf '%s\n' '#!/bin/bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'LOG_FILE="${BARISTA_YABAI_TEST_LOG_FILE:?missing log file}"'
  printf '%s\n' 'STATE_FILE="${BARISTA_YABAI_TEST_STATE_FILE:?missing state file}"'
  printf '%s\n' ''
  printf '%s\n' 'read_state() {'
  printf '%s\n' '  local key="$1"'
  printf '%s\n' '  awk -F= -v key="$key" '\''$1 == key { print $2; exit }'\'' "$STATE_FILE" 2>/dev/null || true'
  printf '%s\n' '}'
  printf '%s\n' ''
  printf '%s\n' 'write_state() {'
  printf '%s\n' '  local key="$1"'
  printf '%s\n' '  local value="$2"'
  printf '%s\n' '  local temp_file="${STATE_FILE}.tmp"'
  printf '%s\n' '  awk -F= -v key="$key" -v value="$value" '\'''
  printf '%s\n' '    BEGIN { updated = 0 }'
  printf '%s\n' '    $1 == key { print key "=" value; updated = 1; next }'
  printf '%s\n' '    { print }'
  printf '%s\n' '    END { if (!updated) print key "=" value }'
  printf '%s\n' '  '\'' "$STATE_FILE" 2>/dev/null > "$temp_file" || true'
  printf '%s\n' '  mv "$temp_file" "$STATE_FILE"'
  printf '%s\n' '}'
  printf '%s\n' ''
  printf '%s\n' 'printf "%s\n" "$*" >> "$LOG_FILE"'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--windows" ] && [ "${4:-}" = "--window" ] && [ $# -eq 4 ]; then'
  printf '%s\n' '  printf '\''{"id":42,"app":"Ghostty","space":%s,"display":%s,"has-focus":true,"is-floating":%s,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}\n'\'' "$(read_state space)" "$(read_state display)" "$(read_state floating)"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--windows" ] && [ "${4:-}" = "--window" ] && [ $# -eq 5 ]; then'
  printf '%s\n' '  printf '\''{"id":42,"app":"Ghostty","space":%s,"display":%s,"has-focus":true,"is-floating":%s,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}\n'\'' "$(read_state space)" "$(read_state display)" "$(read_state floating)"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ] && [ "${4:-}" = "--space" ]; then'
  printf '%s\n' '  case "${5:-}" in'
  printf '%s\n' '    1) printf '\''{"index":1,"display":1,"type":"bsp"}\n'\'' ;;'
  printf '%s\n' '    9) printf '\''{"index":9,"display":2,"type":"float"}\n'\'' ;;'
  printf '%s\n' '    3) printf '\''{"index":3,"display":1,"type":"bsp"}\n'\'' ;;'
  printf '%s\n' '    *) printf '\''{"index":%s,"display":1,"type":"bsp"}\n'\'' "${5:-0}" ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ] && [ $# -eq 3 ]; then'
  printf '%s\n' '  printf '\''[{"index":1,"display":1,"type":"bsp"},{"index":9,"display":2,"type":"float"}]\n'\'''
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ] && [ "${4:-}" = "--display" ]; then'
  printf '%s\n' '  printf '\''[{"index":1},{"index":9}]\n'\'''
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "window" ] && [ "${3:-}" = "42" ] && [ "${4:-}" = "--space" ]; then'
  printf '%s\n' '  case "${5:-}" in'
  printf '%s\n' '    next)'
  printf '%s\n' '      write_state space 9'
  printf '%s\n' '      write_state display 2'
  printf '%s\n' '      ;;'
  printf '%s\n' '    prev)'
  printf '%s\n' '      write_state space 3'
  printf '%s\n' '      write_state display 1'
  printf '%s\n' '      ;;'
  printf '%s\n' '    *)'
  printf '%s\n' '      write_state space "${5:-0}"'
  printf '%s\n' '      if [ "${5:-}" = "9" ]; then'
  printf '%s\n' '        write_state display 2'
  printf '%s\n' '      fi'
  printf '%s\n' '      ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "window" ] && [ "${3:-}" = "42" ] && [ "${4:-}" = "--display" ]; then'
  printf '%s\n' '  case "${5:-}" in'
  printf '%s\n' '    next)'
  printf '%s\n' '      write_state display 2'
  printf '%s\n' '      write_state space 9'
  printf '%s\n' '      ;;'
  printf '%s\n' '    prev)'
  printf '%s\n' '      write_state display 1'
  printf '%s\n' '      write_state space 3'
  printf '%s\n' '      ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "window" ] && [ "${3:-}" = "42" ] && [ "${4:-}" = "--toggle" ] && [ "${5:-}" = "float" ]; then'
  printf '%s\n' '  write_state floating true'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' ''
  printf '%s\n' 'exit 1'
} > "$BIN_DIR/yabai"
chmod +x "$BIN_DIR/yabai"

JQ_BIN="$(command -v jq)"
[ -n "$JQ_BIN" ] || { echo "FAIL: jq is required for test_yabai_control_window_rules.sh" >&2; exit 1; }

reset_state() {
  printf '%s\n' 'space=1' 'display=1' 'floating=false' > "$STATE_FILE"
  : > "$LOG_FILE"
}

assert_log_contains() {
  local expected="$1"
  grep -Fxq -- "$expected" "$LOG_FILE" || {
    echo "FAIL: expected log line '$expected'" >&2
    cat "$LOG_FILE" >&2
    exit 1
  }
}

assert_log_not_contains() {
  local unexpected="$1"
  if grep -Fxq -- "$unexpected" "$LOG_FILE"; then
    echo "FAIL: unexpected log line '$unexpected'" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
}

run_control() {
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_YABAI_TEST_LOG_FILE="$LOG_FILE" \
    BARISTA_YABAI_TEST_STATE_FILE="$STATE_FILE" \
    YABAI_BIN="$BIN_DIR/yabai" \
    JQ_BIN="$JQ_BIN" \
    "$SCRIPT" "$@"
}

reset_state
run_control window-space 9
assert_log_contains "-m query --windows --window"
assert_log_contains "-m window 42 --space 9"
assert_log_contains "-m query --windows --window 42"
assert_log_contains "-m query --spaces --space 9"
assert_log_contains "-m window 42 --toggle float"

reset_state
run_control window-display-next
assert_log_contains "-m window 42 --display next"
assert_log_contains "-m query --spaces --space 9"
assert_log_contains "-m window 42 --toggle float"

reset_state
run_control window-space 3
assert_log_contains "-m window 42 --space 3"
assert_log_contains "-m query --spaces --space 3"
assert_log_not_contains "-m window 42 --toggle float"

printf '%s\n' 'space=1' 'display=1' 'floating=true' > "$STATE_FILE"
: > "$LOG_FILE"
run_control window-space next
assert_log_contains "-m window 42 --space next"
assert_log_contains "-m query --spaces --space 9"
assert_log_not_contains "-m window 42 --toggle float"

reset_state
run_control window-space-float
assert_log_contains "-m query --spaces"
assert_log_contains "-m window 42 --space 9"
assert_log_contains "-m window 42 --toggle float"

printf '%s\n' 'space=9' 'display=2' 'floating=false' > "$STATE_FILE"
: > "$LOG_FILE"
run_control window-adopt-space-mode
assert_log_contains "-m query --windows --window"
assert_log_contains "-m query --windows --window 42"
assert_log_contains "-m query --spaces --space 9"
assert_log_contains "-m window 42 --toggle float"

printf '%s\n' 'space=1' 'display=1' 'floating=true' > "$STATE_FILE"
: > "$LOG_FILE"
run_control window-adopt-space-mode
assert_log_contains "-m query --spaces --space 1"
assert_log_contains "-m window 42 --toggle float"

printf 'test_yabai_control_window_rules.sh: ok\n'
