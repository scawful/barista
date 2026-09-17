#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/menu_action.cpp"
SHELL_FALLBACK="$ROOT_DIR/plugins/menu_action.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin with spaces"
SKETCHYBAR="$BIN_DIR/sketchybar"
HELPER="$TMP_DIR/menu_action"
LOG="$TMP_DIR/sketchybar.log"
ACTION_FLAG="$TMP_DIR/action.done"
CXX_BIN="${CXX:-$(command -v c++ 2>/dev/null || true)}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

[ -n "$CXX_BIN" ] || {
  echo "FAIL: a C++ compiler is required" >&2
  exit 1
}
mkdir -p "$BIN_DIR"
cat > "$SKETCHYBAR" <<EOF
#!/bin/bash
{
  printf 'CALL'
  printf '\t<%s>' "\$@"
  printf '\n'
} >> "$LOG"
EOF
chmod +x "$SKETCHYBAR"
"$CXX_BIN" -std=c++17 -Wall -Wextra -Werror "$SOURCE" -o "$HELPER"

ITEM='menu row;not shell'
POPUP='popup name $(literal)'
BARISTA_SKETCHYBAR_BIN="$SKETCHYBAR" \
MENU_ACTION_RESET_DELAY=0 \
MENU_ACTION_CMD="printf done > '$ACTION_FLAG'" \
  "$HELPER" "$ITEM" "$POPUP"

for _ in $(seq 1 100); do
  [ -f "$ACTION_FLAG" ] && [ "$(wc -l < "$LOG")" -ge 2 ] && break
  sleep 0.01
done
[ -f "$ACTION_FLAG" ] || { echo "FAIL: native menu action command did not run" >&2; exit 1; }
[ "$(wc -l < "$LOG")" -eq 2 ] || { echo "FAIL: native helper should issue one batch and one reset" >&2; cat "$LOG" >&2; exit 1; }
first_call="$(sed -n '1p' "$LOG")"
[[ "$first_call" == *$'<--set>\t<menu row;not shell>\t<background.drawing=on>'* ]] || {
  echo "FAIL: native helper did not preserve the item argv" >&2
  exit 1
}
[[ "$first_call" == *$'<--set>\t<popup name $(literal)>\t<popup.drawing=off>'* ]] || {
  echo "FAIL: native helper did not batch popup dismissal" >&2
  exit 1
}

oversized="$(printf '%0256d' 0)"
if BARISTA_SKETCHYBAR_BIN="$SKETCHYBAR" "$HELPER" "$oversized" ""; then
  echo "FAIL: native helper must reject oversized item names" >&2
  exit 1
fi

: > "$LOG"
BARISTA_SKETCHYBAR_BIN="$SKETCHYBAR" \
MENU_ACTION_RESET_DELAY=0 \
MENU_ACTION_CMD="" \
  bash "$SHELL_FALLBACK" "$ITEM" "$POPUP"

[ "$(wc -l < "$LOG")" -eq 2 ] || { echo "FAIL: shell fallback should issue one batch and one reset" >&2; cat "$LOG" >&2; exit 1; }
shell_first="$(sed -n '1p' "$LOG")"
[[ "$shell_first" == *$'<--set>\t<menu row;not shell>\t<background.drawing=on>'* \
  && "$shell_first" == *$'<--set>\t<popup name $(literal)>\t<popup.drawing=off>'* ]] || {
  echo "FAIL: shell fallback must preserve argv and batch its first update" >&2
  exit 1
}

printf 'test_menu_action.sh: ok\n'
