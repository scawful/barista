#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_SOURCE="$ROOT_DIR/helpers/popup_hover.c"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
HELPER_BIN="$TMP_DIR/popup_hover"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/sketchybar" <<'SH'
#!/bin/bash
set -euo pipefail

log_file="${BARISTA_POPUP_HOVER_TEST_LOG:?}"
printf 'argc\t%d\n' "$#" > "$log_file"
index=1
for argument in "$@"; do
  printf 'arg\t%d\t%s\n' "$index" "$argument" >> "$log_file"
  index=$((index + 1))
done
SH
chmod +x "$BIN_DIR/sketchybar"

CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [[ -z "$CC_BIN" ]]; then
  printf 'test_popup_hover.sh: skipped (C compiler unavailable)\n'
  exit 0
fi
"$CC_BIN" -std=c99 -O2 -Wall -Wextra -o "$HELPER_BIN" "$HELPER_SOURCE"

assert_arg() {
  local index="$1"
  local expected="$2"
  grep -Fqx -- $'arg\t'"$index"$'\t'"$expected" "$LOG_FILE" || {
    echo "FAIL: expected argument $index to be: $expected" >&2
    cat "$LOG_FILE" >&2
    exit 1
  }
}

run_helper() {
  env -i \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$TMP_DIR" \
    BARISTA_POPUP_HOVER_TEST_LOG="$LOG_FILE" \
    "$@" \
    "$HELPER_BIN"
}

run_helper \
  NAME="popup.row" \
  SENDER="mouse.entered" \
  SUBMENU_PARENT="apple_menu" \
  POPUP_HOVER_COLOR="0x40123456" \
  POPUP_HOVER_BORDER_WIDTH="2" \
  POPUP_HOVER_BORDER_COLOR="0x60abcdef" \
  POPUP_HOVER_ANIMATION_CURVE="sin" \
  POPUP_HOVER_ANIMATION_DURATION="3"

grep -Fqx $'argc\t9' "$LOG_FILE" || { echo "FAIL: animated border enter argument count" >&2; exit 1; }
assert_arg 1 "--animate"
assert_arg 2 "sin"
assert_arg 3 "3"
assert_arg 4 "--set"
assert_arg 5 "popup.row"
assert_arg 6 "background.drawing=on"
assert_arg 7 "background.color=0x40123456"
assert_arg 8 "background.border_width=2"
assert_arg 9 "background.border_color=0x60abcdef"

PARENT_FILE="$TMP_DIR/sketchybar_popup_state/active_parent"
[[ "$(cat "$PARENT_FILE")" == "apple_menu" ]] || {
  echo "FAIL: popup hover should record the submenu parent" >&2
  exit 1
}

run_helper \
  NAME="popup.row" \
  SENDER="mouse.exited" \
  POPUP_HOVER_EXIT_CURVE="linear" \
  POPUP_HOVER_EXIT_DURATION="2"

grep -Fqx $'argc\t7' "$LOG_FILE" || { echo "FAIL: animated exit argument count" >&2; exit 1; }
assert_arg 1 "--animate"
assert_arg 2 "linear"
assert_arg 3 "2"
assert_arg 4 "--set"
assert_arg 5 "popup.row"
assert_arg 6 "background.drawing=off"
assert_arg 7 "background.border_width=0"

SENTINEL="$TMP_DIR/shell-interpolation-must-not-run"
HOSTILE_NAME="popup.row; touch $SENTINEL"
run_helper \
  NAME="$HOSTILE_NAME" \
  SENDER="mouse.entered" \
  POPUP_HOVER_COLOR="0x40fedcba"

grep -Fqx $'argc\t4' "$LOG_FILE" || { echo "FAIL: hostile-name enter argument count" >&2; exit 1; }
assert_arg 1 "--set"
assert_arg 2 "$HOSTILE_NAME"
assert_arg 3 "background.drawing=on"
assert_arg 4 "background.color=0x40fedcba"
[[ ! -e "$SENTINEL" ]] || {
  echo "FAIL: hostile NAME must not reach shell interpolation" >&2
  exit 1
}

printf 'test_popup_hover.sh: ok\n'
