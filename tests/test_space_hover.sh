#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/space.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LOG_FILE="$TMP_DIR/sketchybar.log"
STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"
CONFIG_DIR="$TMP_DIR/config"
STYLE_DIR="$CONFIG_DIR/cache/space_visuals/style_state"
mkdir -p "$CONFIG_DIR/cache/hover" "$STYLE_DIR"
cat > "$STYLE_DIR/space.12.state" <<'EOF'
state=focused
label.drawing=off
background.drawing=on
background.color=0xffd8c4ff
background.border_width=2
background.border_color=0xffffffff
icon.color=0xff11111b
EOF

cat > "$TMP_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="${BARISTA_TEST_LOG:?}"

case "${1:-}" in
  --query)
    cat <<'JSON'
{"geometry":{"background":{"drawing":"on","color":"0xFFD8C4FF"}},"icon":{"color":"0xff11111b"}}
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
  BARISTA_TEST_LOG="$LOG_FILE"
  BARISTA_HOVER_STATE_DIR="$STATE_DIR"
  CONFIG_DIR="$CONFIG_DIR"
  NAME="space.12"
)

env "${COMMON_ENV[@]}" SENDER="mouse.entered" "$SCRIPT"

CACHE_FILE="$STATE_DIR/space.12.state"
[ -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file after mouse.entered" >&2; exit 1; }
grep -Fq $'set\tspace.12 label.drawing=off background.drawing=on background.color=0xffd8c4ff background.border_width=2 background.border_color=0xffffffff icon.color=0xff11111b' "$LOG_FILE" || {
  echo "FAIL: expected focused chip to stay focused on mouse.entered" >&2
  exit 1
}

env "${COMMON_ENV[@]}" SENDER="mouse.exited" "$SCRIPT"

[ ! -f "$CACHE_FILE" ] || { echo "FAIL: expected hover state cache file to be removed after mouse.exited" >&2; exit 1; }
grep -Fq $'set\tspace.12 label.drawing=off background.drawing=on background.color=0xffd8c4ff background.border_width=2 background.border_color=0xffffffff icon.color=0xff11111b' "$LOG_FILE" || {
  echo "FAIL: expected saved focused visual state to be restored on mouse.exited" >&2
  exit 1
}
if grep -Fq $'trigger\tspace_visual_refresh' "$LOG_FILE"; then
  echo "FAIL: restore path should not need a fallback trigger when cached state is present" >&2
  exit 1
fi

rm -f "$LOG_FILE"
env "${COMMON_ENV[@]}" SENDER="mouse.exited" "$SCRIPT"
grep -Fq $'set\tspace.12 label.drawing=off background.drawing=on background.color=0xffd8c4ff background.border_width=2 background.border_color=0xffffffff icon.color=0xff11111b' "$LOG_FILE" || {
  echo "FAIL: mouse.exited should restore the saved style state even without a hover token" >&2
  exit 1
}

echo "PASS: space hover restores cached visual state"
