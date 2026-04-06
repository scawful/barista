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

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$CONFIG_DIR/cache/space_icons" "$BIN_DIR"

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
topology=1 1,1 2
creator_topology=creator_mode=primary|creator_targets=1
visible=1 1
visible_by_display=1:1
active_display=1
space_props=
creator_props=
SIG

printf 'X\n' > "$CONFIG_DIR/cache/space_icons/1"

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
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
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '{"height":28,"items":["front_app"]}\n'
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

if ! grep -Fq -- "--add space space.1" "$LOG_FILE"; then
  echo "FAIL: empty bar snapshot should force full rebuild and add space.1" >&2
  exit 1
fi

if ! grep -Fq -- "icon=X" "$LOG_FILE"; then
  echo "FAIL: full rebuild should apply cached space icon without per-space cache misses" >&2
  exit 1
fi

grep -Fxq 'strategy=full_rebuild' "$METRICS_FILE" || { echo "FAIL: empty bar snapshot should emit full_rebuild metrics" >&2; exit 1; }
grep -Fxq 'removed=0' "$METRICS_FILE" || { echo "FAIL: empty bar snapshot should report zero removed spaces" >&2; exit 1; }
grep -Fxq 'updated=2' "$METRICS_FILE" || { echo "FAIL: full rebuild should report updated spaces" >&2; exit 1; }

printf 'test_simple_spaces_full_rebuild.sh: ok\n'
