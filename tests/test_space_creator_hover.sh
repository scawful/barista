#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/space_creator.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
STATE_DIR="$TMP_DIR/state"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$STATE_DIR"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

COMMON_ENV=(
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar"
  BARISTA_HOVER_STATE_DIR="$STATE_DIR"
  NAME="space_creator.2"
)

env PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" "${COMMON_ENV[@]}" SENDER="mouse.entered" "$SCRIPT"

CACHE_FILE="$STATE_DIR/space_creator.2.state"
[ -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file after mouse.entered" >&2; exit 1; }
grep -Fq $'space_creator.2 background.drawing=on background.color=0x40D8C4FF icon.color=0xFFF5EEFF' "$LOG_FILE" || {
  echo "FAIL: creator hover should use the updated hover chip colors" >&2
  exit 1
}

env PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" "${COMMON_ENV[@]}" SENDER="mouse.exited" "$SCRIPT"

[ ! -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file to be removed after mouse.exited" >&2; exit 1; }
grep -Fq $'space_creator.2 background.drawing=on background.color=0x102a313c icon.color=0xB0bac2de' "$LOG_FILE" || {
  echo "FAIL: creator hover should restore the idle chip styling on mouse.exited" >&2
  exit 1
}

printf 'test_space_creator_hover.sh: ok\n'
