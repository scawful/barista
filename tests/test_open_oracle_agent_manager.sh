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

FAKE_OPEN="$BIN_DIR/open"
cat > "$FAKE_OPEN" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'open:%s\n' "$*" >> "${BARISTA_ORACLE_TEST_LOG:?}"
EOF
chmod +x "$FAKE_OPEN"

OAM_CLIENT="$CODE_DIR/hobby/oracle-agent-manager/client"
OAM_APP_DIR="$OAM_CLIENT/build/Oracle Agent Manager.app"

make_fake_oam() {
  local path="$1" tag="$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/bin/bash\nprintf "%s:\\n" >> "${BARISTA_ORACLE_TEST_LOG:?}"\n' "$tag" > "$path"
  chmod +x "$path"
}

run_launcher() {
  local cortex_cli="$1" fake_cortex_exit="${2:-0}"
  shift
  [[ $# -gt 0 ]] && shift
  HOME="$TEST_HOME" \
    TMPDIR="$TMP_DIR" \
    PATH="/usr/bin:/bin" \
    BARISTA_CONFIG_DIR="$CONFIG_DIR" \
    BARISTA_CODE_DIR="$CODE_DIR" \
    BARISTA_OPEN_BIN="$FAKE_OPEN" \
    BARISTA_ORACLE_TEST_LOG="$LOG_FILE" \
    BARISTA_FAKE_CORTEX_EXIT="$fake_cortex_exit" \
    CORTEX_CLI="$cortex_cli" \
    OAM_APP="" \
    "$SCRIPT" "$@" >/dev/null 2>&1
}

wait_for_log() {
  local needle="$1"
  for _ in $(seq 1 40); do
    grep -Fq "$needle" "$LOG_FILE" && return 0
    sleep 0.05
  done
  return 1
}

wait_for_legacy() {
  wait_for_log 'legacy:'
}

fail() {
  echo "FAIL: $1" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

# OAM SwiftUI client: bundled app first, then release, then debug binary; Cortex untouched.
make_fake_oam "$OAM_CLIENT/.build/debug/oam" "oam-debug"
: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI" 0
wait_for_log 'oam-debug:' || fail "debug oam binary should launch when it is the only OAM build"
grep -Fq 'cortex:' "$LOG_FILE" && fail "Cortex must not run when an OAM build exists"

make_fake_oam "$OAM_CLIENT/.build/release/oam" "oam-release"
: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI" 0
wait_for_log 'oam-release:' || fail "release oam binary should win over debug"
grep -Fq 'oam-debug:' "$LOG_FILE" && fail "debug oam must not launch when release exists"

make_fake_oam "$OAM_APP_DIR/Contents/MacOS/oam" "oam-app-direct"
: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI" 0
[ "$(cat "$LOG_FILE")" = "open:$OAM_APP_DIR" ] || fail "bundled app should open through LaunchServices only"

: > "$LOG_FILE"
run_launcher "$FAKE_CORTEX_CLI" 0 --hub
[ "$(cat "$LOG_FILE")" = "cortex:oracle" ] || fail "--hub should skip the OAM GUI"

rm -rf "$OAM_CLIENT"

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
