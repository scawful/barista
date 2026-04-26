#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/refresh_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
CALLS_LOG="$TMP_DIR/calls.log"
TOPOLOGY_LOG="$TMP_DIR/topology.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/bin" "$CONFIG_DIR/cache/space_visuals" "$CONFIG_DIR/scripts" "$BIN_DIR"

printf '1|1-1,1-2' > "$CONFIG_DIR/.spaces_cache"
printf '1:1' > "$CONFIG_DIR/.spaces_active_cache"
printf 'space.1\nspace.2\n' > "$CONFIG_DIR/cache/space_visuals/space_items"

cat > "$CONFIG_DIR/state.json" <<'STATE'
{
  "appearance": { "bar_height": 28 }
}
STATE

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"has-focus":false,"type":"bsp"}]\n'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
CALLS_LOG="$CALLS_LOG"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf 'query bar\n' >> "\$CALLS_LOG"
  printf '{"height":38,"items":["front_app","front_app_divider","space.1","space.2","space_creator"]}\n'
  exit 0
fi
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "space.1" ]; then
  printf '{"geometry":{"background":{"height":20}}}\n'
  exit 0
fi
printf '%s\n' "\$*" >> "\$CALLS_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$CONFIG_DIR/bin/barista-stats.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
exit 0
EOF
chmod +x "$CONFIG_DIR/bin/barista-stats.sh"

cat > "$CONFIG_DIR/plugins/simple_spaces.sh" <<EOF
#!/bin/bash
set -euo pipefail
printf 'simple_spaces_called\n' >> "$TOPOLOGY_LOG"
cat > "\${BARISTA_SPACE_METRICS_FILE}" <<'METRICS'
strategy=props_only
added=0
removed=0
updated=2
topology_ms=5
METRICS
EOF
chmod +x "$CONFIG_DIR/plugins/simple_spaces.sh"

cat > "$CONFIG_DIR/plugins/space_visuals.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
exit 0
EOF
chmod +x "$CONFIG_DIR/plugins/space_visuals.sh"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  CONFIG_DIR="$CONFIG_DIR" \
  SCRIPTS_DIR="$CONFIG_DIR/scripts" \
  "$SCRIPT"

grep -Fxq 'simple_spaces_called' "$TOPOLOGY_LOG" || { echo "FAIL: refresh_spaces should rerun simple_spaces when live space height does not match the current bar height" >&2; exit 1; }

printf 'test_refresh_spaces_live_height_repair.sh: ok\n'
