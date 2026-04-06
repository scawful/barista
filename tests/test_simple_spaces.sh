#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
METRICS_FILE="$TMP_DIR/space_metrics.env"
YABAI_LOG="$TMP_DIR/yabai.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$BIN_DIR"

cat > "$CONFIG_DIR/state.json" <<'EOF'
{
  "appearance": { "bar_height": 28 },
  "spaces": {
    "experimental_diff_updates": true,
    "creator_mode": "primary"
  }
}
EOF

cat > "$CONFIG_DIR/.spaces_signatures" <<'EOF'
topology=1 1,1 2
creator_topology=creator_mode=per_display|creator_targets=1
visible=1 1
visible_by_display=1:1
active_display=1
space_props=
creator_props=
EOF

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "__YABAI_LOG__"
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":1,"index":2,"is-visible":false,"has-focus":false}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--displays" ] && [ "${4:-}" = "--display" ]; then
  printf '{"index":1}\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--displays" ]; then
  printf '[{"index":1}]\n'
  exit 0
fi
exit 1
EOF
python3 - <<'PY' "$BIN_DIR/yabai" "$YABAI_LOG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
log_path = sys.argv[2]
path.write_text(path.read_text().replace("__YABAI_LOG__", log_path), encoding="utf-8")
PY
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '{"height":28,"items":["front_app","space.1","space.2","space_creator"]}\n'
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

if grep -Fq -- "--remove /space\\..*/" "$LOG_FILE"; then
  echo "FAIL: creator-only change should not remove space items" >&2
  exit 1
fi

if grep -Fq -- "--add space space.1" "$LOG_FILE"; then
  echo "FAIL: creator-only change should not recreate space items" >&2
  exit 1
fi

if ! grep -Fq -- "--remove /space_creator\\..*/ --remove space_creator" "$LOG_FILE"; then
  echo "FAIL: creator-only change should rebuild creator items" >&2
  exit 1
fi

if ! grep -Fq -- "--add item space_creator" "$LOG_FILE"; then
  echo "FAIL: creator-only change should add creator item back" >&2
  exit 1
fi

if ! grep -Fq -- "ignore_association=on" "$LOG_FILE"; then
  echo "FAIL: creator items should stay display-visible instead of binding to one space" >&2
  exit 1
fi

if grep -Eq -- '(^| )space=[0-9]+' "$LOG_FILE"; then
  echo "FAIL: creator items should not bind themselves to a specific visible space" >&2
  exit 1
fi

grep -Fxq 'strategy=creator_only' "$METRICS_FILE" || { echo "FAIL: creator-only path should emit creator_only metrics" >&2; exit 1; }
grep -Fxq 'added=0' "$METRICS_FILE" || { echo "FAIL: creator-only path should report zero added spaces" >&2; exit 1; }
grep -Fxq 'removed=0' "$METRICS_FILE" || { echo "FAIL: creator-only path should report zero removed spaces" >&2; exit 1; }
if grep -Fq -- "-m query --displays" "$YABAI_LOG"; then
  echo "FAIL: normal spaces path should not query displays when the spaces payload already has focus info" >&2
  exit 1
fi

printf 'test_simple_spaces.sh: ok\n'
