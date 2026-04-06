#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/refresh_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
CALLS_LOG="$TMP_DIR/calls.log"
METRICS_PATH_LOG="$TMP_DIR/metrics_path.log"
EXTERNAL_BAR_LOG="$TMP_DIR/external_bar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/bin" "$CONFIG_DIR/cache" "$BIN_DIR"
mkdir -p "$CONFIG_DIR/scripts"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"}]\n'
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
  printf '{"items":["space.1"]}\n'
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
printf '%s\n' "\${BARISTA_SPACE_METRICS_FILE:-}" >> "$METRICS_PATH_LOG"
cat > "\${BARISTA_SPACE_METRICS_FILE}" <<'METRICS'
strategy=full_rebuild
added=1
removed=0
updated=1
topology_ms=5
prepare_ms=3
apply_ms=1
discovery_ms=1
build_ms=1
decision_ms=1
METRICS
EOF
chmod +x "$CONFIG_DIR/plugins/simple_spaces.sh"

cat > "$CONFIG_DIR/plugins/space_visuals.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
exit 0
EOF
chmod +x "$CONFIG_DIR/plugins/space_visuals.sh"

cat > "$CONFIG_DIR/scripts/update_external_bar.sh" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\${1:-}" >> "$EXTERNAL_BAR_LOG"
EOF
chmod +x "$CONFIG_DIR/scripts/update_external_bar.sh"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  CONFIG_DIR="$CONFIG_DIR" \
  SCRIPTS_DIR="$CONFIG_DIR/scripts" \
  "$SCRIPT"

[ "$(wc -l < "$METRICS_PATH_LOG" | tr -d ' ')" = "1" ] || { echo "FAIL: topology path should invoke simple_spaces exactly once" >&2; exit 1; }
METRICS_PATH="$(tail -n 1 "$METRICS_PATH_LOG")"
[ -n "$METRICS_PATH" ] || { echo "FAIL: refresh_spaces should provide a metrics path to simple_spaces" >&2; exit 1; }
case "$METRICS_PATH" in
  "$CONFIG_DIR"/*)
    echo "FAIL: topology metrics temp file should not live under CONFIG_DIR" >&2
    exit 1
    ;;
esac

if find "$CONFIG_DIR" -maxdepth 1 -name '.space_topology_metrics.*' | grep -q .; then
  echo "FAIL: refresh_spaces should not leave topology metrics temp files in CONFIG_DIR" >&2
  exit 1
fi
[ "$(wc -l < "$EXTERNAL_BAR_LOG" | tr -d ' ')" = "1" ] || { echo "FAIL: first topology refresh should apply external bar height once" >&2; exit 1; }

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  CONFIG_DIR="$CONFIG_DIR" \
  SCRIPTS_DIR="$CONFIG_DIR/scripts" \
  "$SCRIPT"

[ "$(wc -l < "$METRICS_PATH_LOG" | tr -d ' ')" = "1" ] || { echo "FAIL: active-only path should not reinvoke simple_spaces" >&2; exit 1; }

if find "$CONFIG_DIR" -maxdepth 1 -name '.space_topology_metrics.*' | grep -q .; then
  echo "FAIL: active-only path should not create topology metrics temp files in CONFIG_DIR" >&2
  exit 1
fi
[ "$(wc -l < "$EXTERNAL_BAR_LOG" | tr -d ' ')" = "1" ] || { echo "FAIL: active-only refresh should not reapply unchanged external bar height" >&2; exit 1; }

printf 'test_refresh_spaces.sh: ok\n'
