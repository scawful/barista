#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test_space_visual_helper.sh: skipped (Darwin only)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/space_visual_helper.m"
TMP_DIR="$(mktemp -d)"
HELPER="$TMP_DIR/space_visual_helper"
YABAI="$TMP_DIR/yabai"
QUERY_LOG="$TMP_DIR/yabai.log"
TIMEOUT_PID_LOG="$TMP_DIR/timeout.pid"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [[ -z "$CC_BIN" ]]; then
  printf 'test_space_visual_helper.sh: skipped (Objective-C compiler unavailable)\n'
  exit 0
fi

"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Foundation \
  "$SOURCE" \
  -o "$HELPER"

cat > "$YABAI" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "$BARISTA_TEST_QUERY_LOG"
[ "${1:-}" = "-m" ] \
  && [ "${2:-}" = "query" ] \
  && [ "${3:-}" = "--windows" ] \
  && [ "${4:-}" = "--space" ] || exit 64

space_index="${5:-}"
case "${BARISTA_TEST_SCENARIO:-success}:$space_index" in
  success:1|failure:1)
    printf '%s\n' \
      '[{"id":99,"app":"Hidden","has-focus":true,"is-minimized":true},{"id":50,"app":"Background","has-focus":false,"is-minimized":false},{"id":10,"app":"Focused","has-focus":true,"is-minimized":false}]'
    ;;
  success:3)
    printf '%s\n' \
      '[{"id":11,"app":"Older","has-focus":false,"is-minimized":false},{"id":20,"app":"Slack\tBeta\nLine","has-focus":false,"is-minimized":false}]'
    ;;
  failure:3)
    exit 2
    ;;
  failed_descendant:*)
    /bin/bash -c '
      trap "" TERM HUP
      /bin/sleep 5
    ' >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$BARISTA_TEST_TIMEOUT_PID_LOG"
    exit 2
    ;;
  successful_descendant:*)
    /bin/bash -c '
      trap "" TERM HUP
      /bin/sleep 5
    ' >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$BARISTA_TEST_TIMEOUT_PID_LOG"
    printf '%s\n' \
      '[{"id":1,"app":"Clean Exit","has-focus":true,"is-minimized":false}]'
    ;;
  timeout:*)
    printf '%s\n' "$$" > "$BARISTA_TEST_TIMEOUT_PID_LOG"
    /bin/sleep 5 &
    printf '%s\n' "$!" >> "$BARISTA_TEST_TIMEOUT_PID_LOG"
    wait
    ;;
  orphan:*)
    printf '%s\n' "$$" > "$BARISTA_TEST_TIMEOUT_PID_LOG"
    /bin/bash -c '
      printf "%s\n" "$$" >> "$BARISTA_TEST_TIMEOUT_PID_LOG"
      trap "" TERM HUP
      /bin/sleep 5
    ' &
    exit 0
    ;;
  large:*)
    exec /usr/bin/python3 - <<'PY'
import json

windows = [
    {
        "id": index,
        "app": "Ignored " + ("x" * 48),
        "has-focus": False,
        "is-minimized": True,
    }
    for index in range(5000)
]
windows.append({
    "id": 999999,
    "app": "Large Winner",
    "has-focus": False,
    "is-minimized": False,
})
print(json.dumps(windows, separators=(",", ":")))
PY
    ;;
  *)
    printf '[]\n'
    ;;
esac
EOF
chmod +x "$YABAI"

run_helper() {
  env -i \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP_DIR/home" \
    BARISTA_YABAI_BIN="$YABAI" \
    BARISTA_TEST_QUERY_LOG="$QUERY_LOG" \
    BARISTA_TEST_TIMEOUT_PID_LOG="$TIMEOUT_PID_LOG" \
    BARISTA_TEST_SCENARIO="${BARISTA_TEST_SCENARIO:-success}" \
    "$HELPER" "$@"
}

: > "$QUERY_LOG"
output="$(run_helper visible-apps 1 3)"
[ "$output" = $'1\tFocused\n3\tSlack Beta Line' ] || {
  echo "FAIL: helper should prefer focused windows, then highest IDs, and sanitize fields" >&2
  printf 'output=%q\n' "$output" >&2
  exit 1
}
[ "$(wc -l < "$QUERY_LOG" | tr -d ' ')" = "2" ] || {
  echo "FAIL: helper should issue one scoped query per requested visible space" >&2
  exit 1
}
grep -Fqx -- '-m query --windows --space 1' "$QUERY_LOG" || {
  echo "FAIL: first scoped query was not passed as an argument vector" >&2
  exit 1
}
grep -Fqx -- '-m query --windows --space 3' "$QUERY_LOG" || {
  echo "FAIL: second scoped query was not passed as an argument vector" >&2
  exit 1
}

set +e
failure_output="$(BARISTA_TEST_SCENARIO=failure run_helper visible-apps 1 3)"
failure_status=$?
set -e
[ "$failure_status" -eq 1 ] || {
  echo "FAIL: a failed scoped query should fail the helper for shell fallback" >&2
  exit 1
}
[ "$failure_output" = $'1\tFocused' ] || {
  echo "FAIL: successful records should remain deterministic before fallback" >&2
  exit 1
}

set +e
BARISTA_TEST_SCENARIO=failed_descendant run_helper visible-apps 1 >/dev/null
failed_descendant_status=$?
set -e
[ "$failed_descendant_status" -eq 1 ] || {
  echo "FAIL: a failed query with a descendant should select the shell fallback" >&2
  exit 1
}
while IFS= read -r failed_descendant_pid; do
  [ -n "$failed_descendant_pid" ] || continue
  if kill -0 "$failed_descendant_pid" >/dev/null 2>&1; then
    echo "FAIL: failed query left its process-group descendant alive (pid=$failed_descendant_pid)" >&2
    exit 1
  fi
done < "$TIMEOUT_PID_LOG"

successful_descendant_output="$(
  BARISTA_TEST_SCENARIO=successful_descendant run_helper visible-apps 1
)"
[ "$successful_descendant_output" = $'1\tClean Exit' ] || {
  echo "FAIL: a successful query should retain valid output while cleaning descendants" >&2
  exit 1
}
while IFS= read -r successful_descendant_pid; do
  [ -n "$successful_descendant_pid" ] || continue
  if kill -0 "$successful_descendant_pid" >/dev/null 2>&1; then
    echo "FAIL: successful query left its process-group descendant alive (pid=$successful_descendant_pid)" >&2
    exit 1
  fi
done < "$TIMEOUT_PID_LOG"

large_output="$(BARISTA_TEST_SCENARIO=large run_helper visible-apps 1)"
[ "$large_output" = $'1\tLarge Winner' ] || {
  echo "FAIL: native capture should drain output larger than a pipe buffer before waiting" >&2
  exit 1
}

rm -f "$TMP_DIR/should-not-exist"
run_helper visible-apps "1;touch $TMP_DIR/should-not-exist" >/dev/null
[ ! -e "$TMP_DIR/should-not-exist" ] || {
  echo "FAIL: a space argument must never be evaluated by a shell" >&2
  exit 1
}

started_at="$(python3 - <<'PY'
import time
print(time.monotonic_ns())
PY
)"
set +e
BARISTA_TEST_SCENARIO=timeout run_helper visible-apps 1 >/dev/null
timeout_status=$?
set -e
finished_at="$(python3 - <<'PY'
import time
print(time.monotonic_ns())
PY
)"
[ "$timeout_status" -eq 1 ] || {
  echo "FAIL: timed-out scoped queries should select the shell fallback" >&2
  exit 1
}
elapsed_ms=$(((finished_at - started_at) / 1000000))
[ "$elapsed_ms" -lt 2000 ] || {
  echo "FAIL: native query timeout exceeded its bounded return window (${elapsed_ms}ms)" >&2
  exit 1
}
while IFS= read -r timeout_pid; do
  [ -n "$timeout_pid" ] || continue
  if kill -0 "$timeout_pid" >/dev/null 2>&1; then
    echo "FAIL: timed-out native query process group survived helper exit (pid=$timeout_pid)" >&2
    exit 1
  fi
done < "$TIMEOUT_PID_LOG"

set +e
BARISTA_TEST_SCENARIO=orphan run_helper visible-apps 1 >/dev/null
orphan_status=$?
set -e
[ "$orphan_status" -eq 1 ] || {
  echo "FAIL: inherited output from an orphaned query group should select the shell fallback" >&2
  exit 1
}
while IFS= read -r orphan_pid; do
  [ -n "$orphan_pid" ] || continue
  if kill -0 "$orphan_pid" >/dev/null 2>&1; then
    echo "FAIL: query process group survived after its leader exited (pid=$orphan_pid)" >&2
    exit 1
  fi
done < "$TIMEOUT_PID_LOG"

printf 'test_space_visual_helper.sh: ok\n'
