#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/scripts/open_local_workflow.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/actions.log"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$BIN_DIR" "$TMP_DIR/workspace"

cat >"$BIN_DIR/osascript" <<'SH'
#!/usr/bin/env bash
printf 'osascript:%s\n' "$*" >>"${WORKFLOW_TEST_LOG:?}"
SH
cat >"$BIN_DIR/open" <<'SH'
#!/usr/bin/env bash
printf 'open:%s\n' "$*" >>"${WORKFLOW_TEST_LOG:?}"
SH
for name in antigravity claude ws stop-agents; do
  cat >"$BIN_DIR/$name" <<'SH'
#!/usr/bin/env bash
printf 'tool:%s:%s\n' "$(basename "$0")" "$*" >>"${WORKFLOW_TEST_LOG:?}"
SH
  chmod +x "$BIN_DIR/$name"
done
chmod +x "$BIN_DIR/osascript" "$BIN_DIR/open"

run_workflow() {
  env \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    WORKFLOW_TEST_LOG="$LOG_FILE" \
    BARISTA_GHOSTTY_APP="$TMP_DIR/missing/Ghostty.app" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_OPEN_BIN="$BIN_DIR/open" \
    ANTIGRAVITY_LAUNCHER="$BIN_DIR/antigravity" \
    CLAUDE_LAUNCHER="$BIN_DIR/claude" \
    WS_LAUNCHER="$BIN_DIR/ws" \
    STOP_AGENTS_LAUNCHER="$BIN_DIR/stop-agents" \
    bash "$RUNNER" "$@"
}

run_workflow antigravity
run_workflow claude-code
run_workflow workspace-navigator
run_workflow open-path "$TMP_DIR/workspace"
run_workflow stop-managed-agents

grep -Fq "$BIN_DIR/antigravity" "$LOG_FILE"
grep -Fq "$BIN_DIR/claude" "$LOG_FILE"
grep -Eq "$BIN_DIR/ws.*explore" "$LOG_FILE"
grep -Fqx "open:$TMP_DIR/workspace" "$LOG_FILE"
grep -Fqx 'tool:stop-agents:--managed' "$LOG_FILE"

printf 'test_open_local_workflow.sh: ok\n'
