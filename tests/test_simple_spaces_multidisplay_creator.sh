#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
METRICS_FILE="$TMP_DIR/space_metrics.env"

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
    "creator_mode": "per_display"
  }
}
STATE

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":1,"index":2,"is-visible":false,"has-focus":false},{"display":2,"index":3,"is-visible":true,"has-focus":false}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--displays" ] && [ "${4:-}" = "--display" ]; then
  printf '{"index":1}\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--displays" ]; then
  printf '[{"index":1},{"index":2}]\n'
  exit 0
fi
exit 1
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '{"height":28,"items":["front_app","front_app_divider"]}\n'
  exit 0
fi
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "front_app" ]; then
  printf '{}\n'
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
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

if ! grep -Fq -- '--add item space_creator.1 left' "$LOG_FILE"; then
  echo "FAIL: per-display mode should create a creator item for display 1" >&2
  exit 1
fi

if ! grep -Fq -- '--add item space_creator.2 left' "$LOG_FILE"; then
  echo "FAIL: per-display mode should create a creator item for display 2" >&2
  exit 1
fi

if ! grep -Fq -- 'space_creator.1 display=1 ignore_association=off' "$LOG_FILE"; then
  echo "FAIL: display 1 creator should honor its display association" >&2
  exit 1
fi

if ! grep -Eq -- 'space_creator\.1.*associated_display=1 associated_space=1,2 --subscribe space_creator\.1' "$LOG_FILE"; then
  echo "FAIL: display 1 creator should bind to every space on display 1" >&2
  exit 1
fi

if ! grep -Fq -- 'space_creator.2 display=2 ignore_association=off' "$LOG_FILE"; then
  echo "FAIL: display 2 creator should honor its display association" >&2
  exit 1
fi

if ! grep -Eq -- 'space_creator\.2.*associated_display=2 associated_space=3 --subscribe space_creator\.2' "$LOG_FILE"; then
  echo "FAIL: display 2 creator should bind to every space on display 2" >&2
  exit 1
fi

printf 'test_simple_spaces_multidisplay_creator.sh: ok\n'
