#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
YABAI_LOG="$TMP_DIR/yabai.log"
METRICS_FILE="$TMP_DIR/space_metrics.env"
SHARED_SPACES='[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":1,"index":2,"is-visible":false,"has-focus":false}]'

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$BIN_DIR"

cat > "$CONFIG_DIR/state.json" <<'STATE'
{
  "appearance": { "bar_height": 28 },
  "spaces": {
    "experimental_diff_updates": true,
    "creator_mode": "primary"
  }
}
STATE

cat > "$BIN_DIR/yabai" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$YABAI_LOG"
if [ "\${1:-}" = "-m" ] && [ "\${2:-}" = "query" ] && [ "\${3:-}" = "--displays" ]; then
  printf '[{"index":1}]\n'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '{"height":28,"items":["front_app","front_app_divider"]}\n'
  exit 0
fi
printf '%s\n' "\$*" >> "\$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  BARISTA_ALL_SPACES_DATA="$SHARED_SPACES" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

if [ -f "$YABAI_LOG" ] && grep -Fq -- '-m query --spaces' "$YABAI_LOG"; then
  echo "FAIL: shared spaces payload should let simple_spaces skip yabai --spaces" >&2
  exit 1
fi

if ! grep -Fq -- '--add space space.1' "$LOG_FILE"; then
  echo "FAIL: shared spaces payload should still drive normal space creation" >&2
  exit 1
fi

printf 'test_simple_spaces_shared_payload.sh: ok\n'
