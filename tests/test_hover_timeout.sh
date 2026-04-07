#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/clock.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$TMP_DIR" \
  NAME="clock" \
  SENDER="mouse.entered" \
  BARISTA_HOVER_COLOR="0x40abcdef" \
  BARISTA_HOVER_TIMEOUT="0.01" \
  "$SCRIPT"

sleep 0.05

if ! grep -Fq -- 'background.drawing=on background.color=0x40abcdef' "$LOG_FILE"; then
  echo "FAIL: clock hover should highlight immediately" >&2
  exit 1
fi

if ! grep -Fq -- 'background.drawing=off' "$LOG_FILE"; then
  echo "FAIL: clock hover highlight should auto-clear after timeout" >&2
  exit 1
fi

printf 'test_hover_timeout.sh: ok\n'
