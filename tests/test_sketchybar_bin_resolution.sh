#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
LOG_FILE="$TMP_DIR/sketchybar.log"
mkdir -p "$BIN_DIR" "$CONFIG_DIR/cache/space_visuals/style_state"

cat > "$BIN_DIR/sketchybar" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
exit 0
STUB
chmod +x "$BIN_DIR/sketchybar"

cat > "$BIN_DIR/yabai" <<'STUB'
#!/bin/bash
printf '[]\n'
exit 0
STUB
chmod +x "$BIN_DIR/yabai"

cat > "$CONFIG_DIR/state.json" <<'JSON'
{
  "space_icons": { "9": "9" }
}
JSON
cat > "$CONFIG_DIR/cache/space_visuals/style_state/space.9.state" <<'EOF_STATE'
state=idle
label.drawing=off
background.drawing=on
background.color=0x18313a46
background.border_width=0
background.border_color=0x00000000
icon.color=0xffbac2de
EOF_STATE

run_with_timeout() {
  perl -e 'alarm shift; exec @ARGV' 2 "$@"
}

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  NAME="space.9" \
  SENDER="mouse.exited" \
  BARISTA_HOVER_TIMEOUT=0 \
  run_with_timeout "$ROOT_DIR/plugins/space.sh"

grep -Fq -- '--set space.9 label.drawing=off background.drawing=on' "$LOG_FILE" || {
  echo "FAIL: space.sh did not call the resolved sketchybar binary" >&2
  exit 1
}

: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  SENDER="manual" \
  BARISTA_ALL_SPACES_DATA='[{"index":9,"display":1,"is-visible":true,"has-focus":true,"type":"bsp"}]' \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=0 \
  run_with_timeout "$ROOT_DIR/plugins/space_visuals.sh"

grep -Fq -- '--set space.9 icon=9 label.drawing=off background.drawing=on' "$LOG_FILE" || {
  echo "FAIL: space_visuals.sh did not call the resolved sketchybar binary" >&2
  exit 1
}

printf 'test_sketchybar_bin_resolution.sh: ok\n'
