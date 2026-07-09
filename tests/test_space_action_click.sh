#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/space_action.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
LOG_FILE="$TMP_DIR/actions.log"
mkdir -p "$BIN_DIR" "$CONFIG_DIR"
printf '{"spaces":{"context_menu_on_right_click":true}}\n' > "$CONFIG_DIR/state.json"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
printf 'yabai\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
printf 'sketchybar\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  YABAI_BIN="$BIN_DIR/yabai" \
  JQ_BIN="" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  BUTTON=2 \
  "$SCRIPT" click --space 4

grep -Fq $'yabai\t-m space --focus 4' "$LOG_FILE" || {
  echo "FAIL: ambiguous numeric button should focus the clicked space" >&2
  exit 1
}

if grep -Fq 'popup.drawing' "$LOG_FILE"; then
  echo "FAIL: ambiguous numeric button should not open a space context menu" >&2
  exit 1
fi

printf 'test_space_action_click.sh: ok\n'
