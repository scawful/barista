#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_SCRIPT="$ROOT_DIR/plugins/popup_anchor.sh"
HELPER_SOURCE="$ROOT_DIR/helpers/popup_anchor.c"
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

cat > "$BIN_DIR/custom-sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf 'custom\t%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/custom-sketchybar"

run_target_checks() {
  local target="$1"
  : > "$LOG_FILE"

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.entered" \
    BARISTA_HOVER_COLOR="0x40123456" \
    "$target"

  if ! grep -Fq -- 'background.drawing=on background.color=0x40123456' "$LOG_FILE"; then
    echo "FAIL: popup anchor should highlight on hover ($target)" >&2
    exit 1
  fi

  : > "$LOG_FILE"

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.entered" \
    BARISTA_HOVER_COLOR="0x40123456" \
    BARISTA_HOVER_TIMEOUT="0.01" \
    "$target"

  sleep 0.05

  if ! grep -Fq -- 'background.drawing=off background.border_width=0' "$LOG_FILE"; then
    echo "FAIL: popup anchor hover highlight should auto-clear after timeout ($target)" >&2
    exit 1
  fi

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.exited" \
    "$target"

  if ! grep -Fq -- 'background.drawing=off background.border_width=0' "$LOG_FILE"; then
    echo "FAIL: popup anchor should clear hover highlight on exit ($target)" >&2
    exit 1
  fi

  : > "$LOG_FILE"

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.exited" \
    BARISTA_ANCHOR_IDLE_DRAWING="on" \
    BARISTA_ANCHOR_IDLE_BG="0x18313a46" \
    BARISTA_ANCHOR_IDLE_BORDER_WIDTH="1" \
    BARISTA_ANCHOR_IDLE_BORDER_COLOR="0x20585b70" \
    "$target"

  if ! grep -Fq -- 'background.drawing=on background.border_width=1 background.border_color=0x20585b70 background.color=0x18313a46' "$LOG_FILE"; then
    echo "FAIL: popup anchor should restore configured idle chip style on exit ($target)" >&2
    exit 1
  fi

  : > "$LOG_FILE"

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.entered" \
    "$target"

  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.exited.global" \
    POPUP_CLOSE_DELAY="0" \
    "$target"

  sleep 0.05

  if ! grep -Fq -- 'popup.drawing=off' "$LOG_FILE"; then
    echo "FAIL: popup anchor should close popup on global exit ($target)" >&2
    exit 1
  fi

  : > "$LOG_FILE"
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    NAME="apple_menu" \
    SENDER="mouse.exited" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/custom-sketchybar" \
    "$target"

  if ! grep -Fq -- $'custom\t--animate sin 12 --set apple_menu' "$LOG_FILE"; then
    echo "FAIL: popup anchor should honor BARISTA_SKETCHYBAR_BIN ($target)" >&2
    exit 1
  fi
}

run_target_checks "$SHELL_SCRIPT"

if command -v clang >/dev/null 2>&1; then
  HELPER_BIN="$TMP_DIR/popup_anchor"
  clang -O2 -Wall -Wextra -o "$HELPER_BIN" "$HELPER_SOURCE"
  run_target_checks "$HELPER_BIN"
fi

printf 'test_popup_anchor.sh: ok\n'
