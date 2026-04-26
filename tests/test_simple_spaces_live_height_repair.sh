#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
METRICS_FILE="$TMP_DIR/space_metrics.env"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$BIN_DIR"

cat > "$CONFIG_DIR/state.json" <<'STATE'
{
  "appearance": { "bar_height": 28 },
  "spaces": {
    "experimental_diff_updates": true,
    "creator_mode": "primary"
  }
}
STATE

cat > "$CONFIG_DIR/.spaces_signatures" <<EOF
topology=1 1,1 2
creator_topology=creator_mode=primary|creator_targets=1
visible=1 1
visible_by_display=1:1
active_display=1
space_props=1|1|30|$CONFIG_DIR/plugins/focus_space.sh 1|7|0x18313a46|10,2|1|30|$CONFIG_DIR/plugins/focus_space.sh 2|7|0x18313a46|10
creator_props=space_creator|1|30|yabai -m space --create|on|
EOF

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":1,"index":2,"is-visible":false,"has-focus":false}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--displays" ]; then
  printf '[{"index":1,"has-focus":true}]\n'
  exit 0
fi
exit 1
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF2
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '{"height":38,"items":["front_app","front_app_divider","space.1","space.2","space_creator"]}\n'
  exit 0
fi
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "space.1" ]; then
  printf '{"geometry":{"background":{"height":20}}}\n'
  exit 0
fi
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "space_creator" ]; then
  printf '{"geometry":{"background":{"height":20}}}\n'
  exit 0
fi
printf '%s\n' "\$*" >> "\$LOG_FILE"
exit 0
EOF2
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

if ! grep -Fq -- '--set space.1' "$LOG_FILE"; then
  echo "FAIL: live height mismatch should update existing spaces in place" >&2
  exit 1
fi

if ! grep -Fq -- 'background.height=30' "$LOG_FILE"; then
  echo "FAIL: live height mismatch should repair spaces to the current bar-derived height" >&2
  exit 1
fi

if ! grep -Fq -- '--set space_creator' "$LOG_FILE"; then
  echo "FAIL: live height mismatch should also repair the creator item height" >&2
  exit 1
fi

grep -Fxq 'strategy=props_only' "$METRICS_FILE" || { echo "FAIL: height repair should stay on the props_only fast path" >&2; exit 1; }

printf 'test_simple_spaces_live_height_repair.sh: ok\n'
