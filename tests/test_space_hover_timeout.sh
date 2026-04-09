#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/space.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
mkdir -p "$TMP_DIR/cache/space_visuals"
printf '2\n' > "$TMP_DIR/cache/space_visuals/last_selected_space"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "space.1" ]; then
  printf 'query\n' >> "$LOG_FILE"
  printf '{"geometry":{"background":{"drawing":"off","color":"0x00000000"}},"icon":{"color":"0xffcdd6f4"}}\n'
  exit 0
fi
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$TMP_DIR" \
  CONFIG_DIR="$TMP_DIR" \
  NAME="space.1" \
  SENDER="mouse.entered" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_HOVER_TIMEOUT="0.01" \
  "$SCRIPT"

sleep 0.05

if ! grep -Fq -- 'background.drawing=on' "$LOG_FILE"; then
  echo "FAIL: space hover should highlight immediately" >&2
  exit 1
fi

if ! grep -Fq -- 'background.drawing=on' "$LOG_FILE"; then
  echo "FAIL: space hover should restore chip drawing after timeout" >&2
  exit 1
fi

if ! grep -Fq -- 'background.color=0x18313a46' "$LOG_FILE"; then
  echo "FAIL: space hover should restore idle chip background after timeout" >&2
  exit 1
fi

if ! grep -Fq -- 'icon.color=0xFFbac2de' "$LOG_FILE"; then
  echo "FAIL: space hover should restore idle icon color after timeout" >&2
  exit 1
fi

if grep -Fq -- 'query' "$LOG_FILE"; then
  echo "FAIL: space hover should not query sketchybar state on hover" >&2
  exit 1
fi

printf 'test_space_hover_timeout.sh: ok\n'
