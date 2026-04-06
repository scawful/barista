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

cat > "$CONFIG_DIR/.spaces_signatures" <<'SIG'
topology=1 2,1 1
creator_topology=creator_mode=primary|creator_targets=1
visible=1 2
visible_by_display=1:2
active_display=1
space_props=
creator_props=
SIG

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true},{"display":1,"index":2,"is-visible":false}]\n'
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
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF2
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
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF2
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

if grep -Fq -- "--remove /space\\..*/" "$LOG_FILE"; then
  echo "FAIL: reorder diff path should not remove space items" >&2
  exit 1
fi

if grep -Fq -- "--add space space.1" "$LOG_FILE"; then
  echo "FAIL: reorder diff path should not recreate space items" >&2
  exit 1
fi

if ! grep -Fq -- "--set space.1 space=1" "$LOG_FILE"; then
  echo "FAIL: reorder diff path should update existing space.1 in place" >&2
  exit 1
fi

if ! grep -Fq -- "--set space.2 space=2" "$LOG_FILE"; then
  echo "FAIL: reorder diff path should update existing space.2 in place" >&2
  exit 1
fi

grep -Fxq 'strategy=incremental_reorder' "$METRICS_FILE" || { echo "FAIL: reorder diff path should emit incremental_reorder metrics" >&2; exit 1; }
grep -Fxq 'added=0' "$METRICS_FILE" || { echo "FAIL: reorder diff path should report zero added spaces" >&2; exit 1; }
grep -Fxq 'removed=0' "$METRICS_FILE" || { echo "FAIL: reorder diff path should report zero removed spaces" >&2; exit 1; }
grep -Fxq 'updated=2' "$METRICS_FILE" || { echo "FAIL: reorder diff path should report updated spaces" >&2; exit 1; }

printf 'test_simple_spaces_diff.sh: ok\n'
