#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/space.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LOG_FILE="$TMP_DIR/sketchybar.log"
STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"

cat > "$TMP_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="${BARISTA_TEST_LOG:?}"

case "${1:-}" in
  --query)
    cat <<'JSON'
{"geometry":{"background":{"drawing":"on","color":"0xFFcba6f7"}},"icon":{"color":"0xff11111b"}}
JSON
    ;;
  --set)
    shift
    printf 'set\t%s\n' "$*" >> "$LOG_FILE"
    ;;
  --trigger)
    shift
    printf 'trigger\t%s\n' "$*" >> "$LOG_FILE"
    ;;
esac
EOF
chmod +x "$TMP_DIR/sketchybar"

COMMON_ENV=(
  BARISTA_SKETCHYBAR_BIN="$TMP_DIR/sketchybar"
  BARISTA_JQ_BIN="$(command -v jq)"
  BARISTA_SPACE_HOVER_STATE_DIR="$STATE_DIR"
  BARISTA_TEST_LOG="$LOG_FILE"
  NAME="space.12"
)

env "${COMMON_ENV[@]}" SENDER="mouse.entered" "$SCRIPT"

CACHE_FILE="$STATE_DIR/space.12.state"
[ -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file after mouse.entered" >&2; exit 1; }
grep -Fq $'set\tspace.12 background.drawing=on background.color=0x60cba6f7 icon.color=0xFFa6adc8' "$LOG_FILE" || {
  echo "FAIL: expected hover set command on mouse.entered" >&2
  exit 1
}

env "${COMMON_ENV[@]}" SENDER="mouse.exited" "$SCRIPT"

[ ! -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file to be removed after mouse.exited" >&2; exit 1; }
grep -Fq $'set\tspace.12 background.drawing=on background.color=0xFFcba6f7 icon.color=0xff11111b' "$LOG_FILE" || {
  echo "FAIL: expected cached visual state to be restored on mouse.exited" >&2
  exit 1
}
if grep -Fq $'trigger\tspace_visual_refresh' "$LOG_FILE"; then
  echo "FAIL: restore path should not need a fallback trigger when cached state is present" >&2
  exit 1
fi

rm -f "$LOG_FILE"
env "${COMMON_ENV[@]}" SENDER="mouse.exited" "$SCRIPT"
if [ -s "$LOG_FILE" ]; then
  echo "FAIL: mouse.exited without cached state should no-op instead of forcing a visual refresh" >&2
  exit 1
fi

echo "PASS: space hover restores cached visual state"
