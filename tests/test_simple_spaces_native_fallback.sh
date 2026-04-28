#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$CONFIG_DIR/bin" "$BIN_DIR"
cp "$ROOT_DIR/plugins/focus_space.sh" "$CONFIG_DIR/plugins/focus_space.sh"
cat > "$CONFIG_DIR/state.json" <<'JSON'
{
  "spaces": {
    "count": 6,
    "creator_mode": "active",
    "experimental_diff_updates": false
  }
}
JSON

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

CONFIG_DIR="$CONFIG_DIR" \
BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
BARISTA_YABAI_BIN="$BIN_DIR/missing-yabai" \
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$SCRIPT"

grep -Fq -- '--add space space.6 left' "$LOG_FILE" || {
  echo "FAIL: native fallback should create spaces from state.spaces.count" >&2
  exit 1
}

grep -Fq -- 'focus_space.sh 6' "$LOG_FILE" || {
  echo "FAIL: native fallback space items should keep click actions" >&2
  exit 1
}

printf 'test_simple_spaces_native_fallback.sh: ok\n'
