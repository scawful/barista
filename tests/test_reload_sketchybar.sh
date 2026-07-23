#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/reload_sketchybar.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
HELPER_LOG="$TMP_DIR/helper.log"
REFRESH_LOG="$TMP_DIR/refresh.log"
NOHUP_LOG="$TMP_DIR/nohup.log"
SKETCHYBAR_LOG="$TMP_DIR/sketchybar.log"
ITEM_FLAG="$TMP_DIR/front_app_loaded"
SPACE_FLAG="$TMP_DIR/space_1_loaded"
QUERY_COUNT_FILE="$TMP_DIR/front_app_query_count"
LOCK_DIR="$TMP_DIR/reload.lock"
LOCK_TIMEOUT_LOG="$TMP_DIR/lock_timeout.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/helpers" "$CONFIG_DIR/plugins" "$BIN_DIR"

cat > "$CONFIG_DIR/helpers/launch_agent_manager.sh" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$HELPER_LOG"
sleep "\${TEST_HELPER_DELAY:-0}"
exit 0
EOF
chmod +x "$CONFIG_DIR/helpers/launch_agent_manager.sh"

cat > "$CONFIG_DIR/plugins/refresh_spaces.sh" <<EOF
#!/bin/bash
printf '%s\n' refresh >> "$REFRESH_LOG"
touch "$SPACE_FLAG"
EOF
chmod +x "$CONFIG_DIR/plugins/refresh_spaces.sh"

cat > "$BIN_DIR/nohup" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$NOHUP_LOG"
exit 99
EOF
chmod +x "$BIN_DIR/nohup"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$SKETCHYBAR_LOG"
case "\${1:-}" in
  --query)
    if [ "\${2:-}" = "front_app" ]; then
      query_count=0
      [ ! -f "$QUERY_COUNT_FILE" ] || query_count=\$(cat "$QUERY_COUNT_FILE")
      query_count=\$((query_count + 1))
      printf '%s\n' "\$query_count" > "$QUERY_COUNT_FILE"
      ready_on_query="\${TEST_FRONT_APP_READY_ON_QUERY:-0}"
      if [ -f "$ITEM_FLAG" ] || { [ "\$ready_on_query" -gt 0 ] && [ "\$query_count" -ge "\$ready_on_query" ]; }; then
        printf '{"label":"loaded"}\n'
      fi
    elif [ "\${2:-}" = "space.1" ] && [ -f "$SPACE_FLAG" ]; then
      printf '{"label":"1"}\n'
    fi
    ;;
  --reload)
    touch "$ITEM_FLAG"
    ;;
esac
EOF
chmod +x "$BIN_DIR/sketchybar"

# A core item that appears on the inclusive boundary should not trigger a
# redundant raw reload.
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_RELOAD_LOCK_DIR="$LOCK_DIR" \
  BARISTA_CORE_ITEM_WAIT_ATTEMPTS="1" \
  TEST_FRONT_APP_READY_ON_QUERY="2" \
  bash "$SCRIPT"

grep -Fqx 'restart homebrew.mxcl.sketchybar' "$HELPER_LOG" || { echo "FAIL: reload helper should restart sketchybar via launch_agent_manager" >&2; exit 1; }
[ ! -f "$ITEM_FLAG" ] || { echo "FAIL: inclusive core-item readiness should avoid the raw reload fallback" >&2; exit 1; }
if grep -Fqx -- '--reload' "$SKETCHYBAR_LOG"; then
  echo "FAIL: boundary-ready core item should not trigger sketchybar --reload" >&2
  exit 1
fi
[ -f "$SPACE_FLAG" ] || { echo "FAIL: boundary-ready reload should still repair a missing space.1" >&2; exit 1; }
[ "$(grep -Fc refresh "$REFRESH_LOG")" -eq 1 ] || { echo "FAIL: boundary-ready reload should run one synchronous space repair" >&2; exit 1; }
[ ! -s "$NOHUP_LOG" ] || { echo "FAIL: reload helper should not schedule a detached repair" >&2; exit 1; }

# A core item that never appears should retain the raw reload recovery path.
: > "$HELPER_LOG"
: > "$REFRESH_LOG"
: > "$SKETCHYBAR_LOG"
rm -f "$ITEM_FLAG" "$SPACE_FLAG" "$QUERY_COUNT_FILE"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_RELOAD_LOCK_DIR="$LOCK_DIR" \
  BARISTA_CORE_ITEM_WAIT_ATTEMPTS="1" \
  bash "$SCRIPT"

grep -Fqx 'restart homebrew.mxcl.sketchybar' "$HELPER_LOG" || { echo "FAIL: fallback reload should restart sketchybar via launch_agent_manager" >&2; exit 1; }
[ -f "$ITEM_FLAG" ] || { echo "FAIL: reload helper should fall back to sketchybar --reload until the core item becomes available" >&2; exit 1; }
[ "$(grep -Fxc -- '--reload' "$SKETCHYBAR_LOG")" -eq 1 ] || { echo "FAIL: missing core item should trigger exactly one raw reload fallback" >&2; exit 1; }
[ -f "$SPACE_FLAG" ] || { echo "FAIL: reload helper should repair a missing space.1 synchronously" >&2; exit 1; }
[ "$(grep -Fc refresh "$REFRESH_LOG")" -eq 1 ] || { echo "FAIL: missing spaces should trigger one synchronous repair" >&2; exit 1; }
[ ! -s "$NOHUP_LOG" ] || { echo "FAIL: reload helper should not schedule a detached repair" >&2; exit 1; }

: > "$HELPER_LOG"
: > "$REFRESH_LOG"
: > "$SKETCHYBAR_LOG"
rm -f "$ITEM_FLAG" "$SPACE_FLAG" "$QUERY_COUNT_FILE"

PIDS=()
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_RELOAD_LOCK_DIR="$LOCK_DIR" \
  BARISTA_RELOAD_LOCK_STALE_SECONDS="0" \
  BARISTA_RELOAD_LOCK_WAIT_SECONDS="20" \
  BARISTA_CORE_ITEM_WAIT_ATTEMPTS="1" \
  TEST_HELPER_DELAY="3" \
  bash "$SCRIPT" &
PIDS+=("$!")

# Join after the lock is older than the deliberately compressed stale
# threshold. A live owner must remain authoritative.
sleep 2
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_RELOAD_LOCK_DIR="$LOCK_DIR" \
  BARISTA_RELOAD_LOCK_STALE_SECONDS="0" \
  BARISTA_RELOAD_LOCK_WAIT_SECONDS="1" \
  BARISTA_CORE_ITEM_WAIT_ATTEMPTS="1" \
  TEST_HELPER_DELAY="3" \
  bash "$SCRIPT" > /dev/null 2> "$LOCK_TIMEOUT_LOG" &
SHORT_WAITER_PID=$!

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_RELOAD_LOCK_DIR="$LOCK_DIR" \
  BARISTA_RELOAD_LOCK_STALE_SECONDS="0" \
  BARISTA_RELOAD_LOCK_WAIT_SECONDS="20" \
  BARISTA_CORE_ITEM_WAIT_ATTEMPTS="1" \
  TEST_HELPER_DELAY="3" \
  bash "$SCRIPT" &
PIDS+=("$!")

if wait "$SHORT_WAITER_PID"; then
  echo "FAIL: a stale-looking live owner should remain authoritative through the waiter deadline" >&2
  exit 1
fi
grep -Fq "SketchyBar reload lock timed out: $LOCK_DIR" "$LOCK_TIMEOUT_LOG" || {
  echo "FAIL: bounded lock waiter should report its timeout" >&2
  exit 1
}

for pid in "${PIDS[@]}"; do
  wait "$pid"
done

[ "$(grep -Fc 'restart homebrew.mxcl.sketchybar' "$HELPER_LOG")" -eq 1 ] || {
  echo "FAIL: overlapping reload invocations must not steal a stale-looking lock from its live owner" >&2
  exit 1
}
[ "$(grep -Fc refresh "$REFRESH_LOG")" -eq 1 ] || {
  echo "FAIL: overlapping reload invocations should run one synchronous space repair" >&2
  exit 1
}
[ ! -s "$NOHUP_LOG" ] || {
  echo "FAIL: overlapping reload invocations should not schedule detached repairs" >&2
  exit 1
}

printf 'test_reload_sketchybar.sh: ok\n'
