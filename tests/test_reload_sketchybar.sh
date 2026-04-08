#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/reload_sketchybar.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
HELPER_LOG="$TMP_DIR/helper.log"
NOHUP_LOG="$TMP_DIR/nohup.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/helpers" "$CONFIG_DIR/plugins" "$BIN_DIR"

cat > "$CONFIG_DIR/helpers/launch_agent_manager.sh" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$HELPER_LOG"
exit 0
EOF
chmod +x "$CONFIG_DIR/helpers/launch_agent_manager.sh"

cat > "$CONFIG_DIR/plugins/refresh_spaces.sh" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$BIN_DIR/nohup" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$NOHUP_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/nohup"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_SPACE_REPAIR_DELAY="1.0" \
  bash "$SCRIPT"

sleep 0.1

grep -Fqx 'restart homebrew.mxcl.sketchybar' "$HELPER_LOG" || { echo "FAIL: reload helper should restart sketchybar via launch_agent_manager" >&2; exit 1; }
grep -Fq 'CONFIG_DIR=' "$NOHUP_LOG" || { echo "FAIL: reload helper should schedule detached space repair with CONFIG_DIR" >&2; exit 1; }
grep -Fq 'refresh_spaces.sh' "$NOHUP_LOG" || { echo "FAIL: reload helper should schedule detached refresh_spaces repair" >&2; exit 1; }
grep -Fq 'sleep 1.0' "$NOHUP_LOG" || { echo "FAIL: reload helper should honor BARISTA_SPACE_REPAIR_DELAY" >&2; exit 1; }

printf 'test_reload_sketchybar.sh: ok\n'
