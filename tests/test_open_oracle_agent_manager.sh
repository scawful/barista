#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/bin/open_oracle_agent_manager.sh"
TMP_DIR="$(mktemp -d)"
TEST_HOME="$TMP_DIR/home"
CONFIG_DIR="$TMP_DIR/config"
CODE_DIR="$TMP_DIR/code"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/launch.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$TEST_HOME" \
  "$CONFIG_DIR" \
  "$BIN_DIR" \
  "$CODE_DIR/hobby/oracle-agent-manager/build"

FAKE_CORTEX_CLI="$BIN_DIR/cortex-cli"
cat > "$FAKE_CORTEX_CLI" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'cortex:%s\n' "$*" >> "${BARISTA_ORACLE_TEST_LOG:?}"
exit "${BARISTA_FAKE_CORTEX_EXIT:-0}"
EOF
chmod +x "$FAKE_CORTEX_CLI"

FAKE_LEGACY_GUI="$CODE_DIR/hobby/oracle-agent-manager/build/oracle_manager_gui"
cat > "$FAKE_LEGACY_GUI" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'legacy:%s\n' "$*" >> "${BARISTA_ORACLE_TEST_LOG:?}"
EOF
chmod +x "$FAKE_LEGACY_GUI"

run_launcher() {
  local fake_cortex_exit="${2:-0}"
  HOME="$TEST_HOME" \
    TMPDIR="$TMP_DIR" \
    PATH="/usr/bin:/bin" \
    BARISTA_CONFIG_DIR="$CONFIG_DIR" \
    BARISTA_CODE_DIR="$CODE_DIR" \
    BARISTA_ORACLE_TEST_LOG="$LOG_FILE" \
    BARISTA_FAKE_CORTEX_EXIT="$fake_cortex_exit" \
    CORTEX_CLI="$1" \
    "$SCRIPT" >/dev/null 2>&1
}

wait_for_legacy() {
  for _ in $(seq 1 40); do
    grep -Fq 'legacy:' "$LOG_FILE" && return 0
    sleep 0.05
  done
  return 1
}

: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI"
[ "$(cat "$LOG_FILE")" = "cortex:oracle" ] || {
  echo "FAIL: Cortex CLI should receive only the oracle command" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

: > "$LOG_FILE"
run_launcher "$BIN_DIR/missing-cortex-cli"
wait_for_legacy || true
grep -Fxq 'legacy:' "$LOG_FILE" || {
  echo "FAIL: missing Cortex CLI should fall back to the legacy GUI" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
if grep -Fq 'cortex:' "$LOG_FILE"; then
  echo "FAIL: unavailable Cortex CLI must not be invoked" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI" 23
wait_for_legacy || true
grep -Fxq 'cortex:oracle' "$LOG_FILE" || {
  echo "FAIL: failing Cortex CLI should still receive the oracle command" >&2
  cat "$LOG_FILE" >&2
  exit 1
}
grep -Fxq 'legacy:' "$LOG_FILE" || {
  echo "FAIL: failing Cortex CLI should fall back to the legacy GUI" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

printf 'test_open_oracle_agent_manager.sh: ok\n'
