#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
SCRIPTS_PATH="$TMP_DIR/scripts dir"
BIN_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR" "$SCRIPTS_PATH" "$BIN_DIR"
cat > "$CONFIG_DIR/state.json" <<EOF
{
  "scripts_dir": "/wrong/top-level",
  "window_manager": "required",
  "paths": {
    "scripts_dir": "$SCRIPTS_PATH"
  },
  "modes": {
    "window_manager": "disabled"
  }
}
EOF

resolved="$(
  BARISTA_JQ_BIN="" \
  CONFIG_DIR="$CONFIG_DIR" \
  STATE_FILE="$CONFIG_DIR/state.json" \
  HOME="$TMP_DIR/home" \
  bash -c '. "$1"; printf "%s|%s" "$SCRIPTS_DIR" "$BARISTA_HOVER_ANIMATION_DURATION"' _ \
    "$ROOT_DIR/plugins/lib/common.sh"
)"
[ "$resolved" = "$SCRIPTS_PATH|8" ] || {
  echo "FAIL: jq-less common state parsing/default mismatch: $resolved" >&2
  exit 1
}

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
EOF
chmod +x "$BIN_DIR/sketchybar"

BARISTA_JQ_BIN="" \
BARISTA_CONFIG_DIR="$CONFIG_DIR" \
BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
bash "$ROOT_DIR/plugins/control_center.sh"

grep -Fq 'label=Bar' "$LOG" || {
  echo "FAIL: control center should read only modes.window_manager without jq" >&2
  exit 1
}

printf 'test_common_state_parsing.sh: ok\n'
