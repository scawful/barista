#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/oracle_triforce.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
SKETCHYBAR_LOG="$TMP_DIR/sketchybar.argv"
STATUS_LOG="$TMP_DIR/status.log"
WIDGET_LOG="$TMP_DIR/widget.log"
PAYLOAD_FILE="$TMP_DIR/status.json"
STATUS_BIN="$TMP_DIR/oos-triforce.sh"
WIDGET_BIN="$TMP_DIR/oos-triforce-widget"
PYTHON_BIN="$(command -v python3)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
: > "$SKETCHYBAR_LOG"
: > "$STATUS_LOG"
: > "$WIDGET_LOG"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
{
  printf 'CALL\n'
  for argument in "\$@"; do
    printf 'ARG\t%s\n' "\$argument"
  done
  printf 'END\n'
} >> "$SKETCHYBAR_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$PAYLOAD_FILE" <<'EOF'
{
  "finish_line": {
    "status_line": "M0*",
    "alerts_level": "warn",
    "focus": {
      "label": "Maku 0",
      "title": "Play Maku \"Tree\" 日本 🌟"
    }
  },
  "commands": {
    "quick": "./Scripts/Build/oos-quick.sh 167",
    "verify": "./Scripts/Build/oos-verify.sh 168"
  }
}
EOF

cat > "$STATUS_BIN" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\t%s\n' "\$PWD" "\$*" >> "$STATUS_LOG"
case "\${BARISTA_TEST_STATUS_MODE:-valid}" in
  invalid) printf '{invalid json\n' ;;
  empty) exit 0 ;;
  fail) exit 23 ;;
  slow) sleep 0.4; cat "$PAYLOAD_FILE" ;;
  hang)
    trap '' TERM
    while :; do sleep 1; done
    ;;
  *) cat "$PAYLOAD_FILE" ;;
esac
EOF
chmod +x "$STATUS_BIN"

cat > "$WIDGET_BIN" <<EOF
#!/bin/bash
printf 'fallback\n' >> "$WIDGET_LOG"
EOF
chmod +x "$WIDGET_BIN"

run_plugin() {
  local sender="$1"
  local status_mode="${2:-valid}"
  local widget_bin="${3:-}"
  local label_override="${4:-}"
  local status_bin="$STATUS_BIN"
  if [ "$status_mode" = "missing" ]; then
    status_bin="$TMP_DIR/missing-oos-triforce.sh"
    status_mode=valid
  fi
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    NAME=triforce \
    SENDER="$sender" \
    BARISTA_HOVER_TIMEOUT=0 \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_ORACLE_REPO_PATH="$TMP_DIR" \
    BARISTA_ORACLE_STATUS_BIN="$status_bin" \
    BARISTA_PYTHON_BIN="$PYTHON_BIN" \
    BARISTA_ORACLE_STATUS_TIMEOUT="${BARISTA_TEST_STATUS_TIMEOUT:-1}" \
    BARISTA_TRIFORCE_LABEL_OVERRIDE="$label_override" \
    BARISTA_TRIFORCE_REFRESH_LOCK_FILE="$TMP_DIR/refresh.lock" \
    BARISTA_TRIFORCE_WIDGET_BIN="$widget_bin" \
    BARISTA_TEST_STATUS_MODE="$status_mode" \
    "$SCRIPT"
}

reset_logs() {
  : > "$SKETCHYBAR_LOG"
  : > "$STATUS_LOG"
  : > "$WIDGET_LOG"
}

# Hover remains cheap and never invokes the Oracle status producer.
run_plugin mouse.entered
grep -Fq $'ARG\tbackground.drawing=on' "$SKETCHYBAR_LOG" || {
  echo "FAIL: hover should still enable highlight" >&2
  exit 1
}
if [ -s "$STATUS_LOG" ]; then
  echo "FAIL: hover should not collect Oracle status" >&2
  exit 1
fi

# The compatibility click marker never owns popup toggle behavior or status.
reset_logs
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  BARISTA_TRIFORCE_ACTION=click \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_ORACLE_STATUS_BIN="$STATUS_BIN" \
  "$SCRIPT"
if [ -s "$SKETCHYBAR_LOG" ] || [ -s "$STATUS_LOG" ]; then
  echo "FAIL: controller click compatibility path should remain a no-op" >&2
  exit 1
fi

# Popup-open refresh takes one canonical snapshot and applies every dynamic
# target through one SketchyBar client call, preserving quoted/Unicode labels.
reset_logs
run_plugin popup_refresh
if [ "$(grep -c '^CALL$' "$SKETCHYBAR_LOG")" -ne 1 ]; then
  echo "FAIL: popup refresh should use one batched SketchyBar call" >&2
  exit 1
fi
EXPECTED_REPO_PATH="$(cd "$TMP_DIR" && pwd -P)"
grep -Fqx "$EXPECTED_REPO_PATH"$'\tstatus-json --barista' "$STATUS_LOG" || {
  echo "FAIL: popup refresh should invoke the canonical status command once from its repo" >&2
  exit 1
}
for expected in \
  $'ARG\tlabel=M0*' \
  $'ARG\ticon.color=0xfff9e2af' \
  $'ARG\toracle.triforce.header' \
  $'ARG\tlabel=ROM: oos168x.sfc' \
  $'ARG\tdrawing=on' \
  $'ARG\tlabel=Focus: Maku "Tree" 日本 🌟' \
  $'ARG\tlabel=Continue: Maku "Tree" 日本 🌟'; do
  grep -Fqx "$expected" "$SKETCHYBAR_LOG" || {
    echo "FAIL: missing batched refresh argument: $expected" >&2
    exit 1
  }
done

# A configured anchor label remains authoritative while popup detail stays
# dynamic.
reset_logs
run_plugin popup_refresh valid "" "Zelda Lab"
grep -Fqx $'ARG\tlabel=Zelda Lab' "$SKETCHYBAR_LOG" || {
  echo "FAIL: configured Triforce label should survive status refresh" >&2
  exit 1
}
if grep -Fqx $'ARG\tlabel=M0*' "$SKETCHYBAR_LOG"; then
  echo "FAIL: automatic status label should not replace a configured label" >&2
  exit 1
fi

# Wake uses the same bounded event path, not a timer.
reset_logs
run_plugin system_woke
if [ "$(wc -l < "$STATUS_LOG" | tr -d ' ')" -ne 1 ] || [ "$(grep -c '^CALL$' "$SKETCHYBAR_LOG")" -ne 1 ]; then
  echo "FAIL: system wake should refresh exactly once" >&2
  exit 1
fi

# Invalid data fails closed without partially mutating the popup.
reset_logs
run_plugin popup_refresh invalid
if [ -s "$SKETCHYBAR_LOG" ]; then
  echo "FAIL: invalid status JSON should not update SketchyBar" >&2
  exit 1
fi

# Portable installations without the canonical producer retain the legacy
# anchor-only widget fallback.
reset_logs
run_plugin popup_refresh missing "$WIDGET_BIN"
if ! grep -Fqx 'fallback' "$WIDGET_LOG"; then
  echo "FAIL: missing canonical status should delegate to the optional fallback widget" >&2
  exit 1
fi
if [ -s "$SKETCHYBAR_LOG" ]; then
  echo "FAIL: fallback test widget should own its own update" >&2
  exit 1
fi

# Concurrent click/wake bursts coalesce behind one status producer.
reset_logs
BARISTA_TEST_STATUS_TIMEOUT=2 run_plugin popup_refresh slow &
first_refresh_pid=$!
attempt=0
while [ ! -s "$STATUS_LOG" ] && [ "$attempt" -lt 100 ]; do
  sleep 0.01
  attempt=$((attempt + 1))
done
BARISTA_TEST_STATUS_TIMEOUT=2 run_plugin system_woke slow
wait "$first_refresh_pid"
if [ "$(wc -l < "$STATUS_LOG" | tr -d ' ')" -ne 1 ]; then
  echo "FAIL: overlapping refreshes should coalesce to one status producer" >&2
  exit 1
fi

# A producer that ignores TERM is killed as a process group and releases the
# coalescing lock, so later clicks cannot accumulate runaway workers.
reset_logs
BARISTA_TEST_STATUS_TIMEOUT=0.1 run_plugin popup_refresh hang
if pgrep -f "$STATUS_BIN" >/dev/null 2>&1; then
  echo "FAIL: timed-out Oracle status process should not survive" >&2
  exit 1
fi
if [ -e "$TMP_DIR/refresh.lock" ]; then
  echo "FAIL: timed-out refresh should release its coalescing lock" >&2
  exit 1
fi
if [ -s "$SKETCHYBAR_LOG" ]; then
  echo "FAIL: timed-out status should not partially update SketchyBar" >&2
  exit 1
fi

# Leaving the popup region still dismisses it without collecting status.
reset_logs
run_plugin mouse.exited.global
grep -Fqx $'ARG\tpopup.drawing=off' "$SKETCHYBAR_LOG" || {
  echo "FAIL: leaving the popup area should dismiss the popup" >&2
  exit 1
}
if [ -s "$STATUS_LOG" ]; then
  echo "FAIL: popup dismissal should not collect Oracle status" >&2
  exit 1
fi

printf 'test_oracle_triforce.sh: ok\n'
