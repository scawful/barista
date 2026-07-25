#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
METRICS_FILE="$TMP_DIR/space_metrics.env"
CLOCK_LOG="$TMP_DIR/perf_clock.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/scripts" "$CONFIG_DIR/cache/space_icons" "$BIN_DIR"

cat > "$CONFIG_DIR/scripts/space_action.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$CONFIG_DIR/scripts/space_action.sh"

cat > "$BIN_DIR/perf_clock" <<'EOF'
#!/bin/bash
values=(1000 1010 1030 1040 1045 1060)
index="$(wc -l < "$BARISTA_PERF_CLOCK_LOG" 2>/dev/null | tr -d ' ' || printf '0')"
printf 'clock\n' >> "$BARISTA_PERF_CLOCK_LOG"
printf '%s\n' "${values[$index]:-${values[${#values[@]}-1]}}"
EOF
chmod +x "$BIN_DIR/perf_clock"
: > "$CLOCK_LOG"
export BARISTA_PERF_CLOCK_BIN="$BIN_DIR/perf_clock"
export BARISTA_PERF_CLOCK_LOG="$CLOCK_LOG"

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
  printf '{"height":28,"items":["front_app","front_app_divider"]}\n'
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

if ! grep -Fq -- "--move space.1 after front_app_divider" "$LOG_FILE"; then
  echo "FAIL: full rebuild should anchor spaces after the front-app divider" >&2
  exit 1
fi

if ! grep -Fq -- "icon=X" "$LOG_FILE"; then
  echo "FAIL: full rebuild should apply cached space icon without per-space cache misses" >&2
  exit 1
fi

grep -Fxq 'strategy=full_rebuild' "$METRICS_FILE" || { echo "FAIL: empty bar snapshot should emit full_rebuild metrics" >&2; exit 1; }
grep -Fxq 'removed=0' "$METRICS_FILE" || { echo "FAIL: empty bar snapshot should report zero removed spaces" >&2; exit 1; }
grep -Fxq 'updated=2' "$METRICS_FILE" || { echo "FAIL: full rebuild should report updated spaces" >&2; exit 1; }
[ "$(wc -l < "$CLOCK_LOG" | tr -d ' ')" = "6" ] || { echo "FAIL: full rebuild should use exactly six native timestamps" >&2; exit 1; }
grep -Fxq 'discovery_ms=10' "$METRICS_FILE" || { echo "FAIL: native discovery timing boundary changed" >&2; exit 1; }
grep -Fxq 'build_ms=20' "$METRICS_FILE" || { echo "FAIL: native build timing boundary changed" >&2; exit 1; }
grep -Fxq 'decision_ms=10' "$METRICS_FILE" || { echo "FAIL: native decision timing boundary changed" >&2; exit 1; }
grep -Fxq 'prepare_ms=40' "$METRICS_FILE" || { echo "FAIL: native prepare timing boundary changed" >&2; exit 1; }
grep -Fxq 'apply_ms=5' "$METRICS_FILE" || { echo "FAIL: native apply timing boundary changed" >&2; exit 1; }
grep -Fxq 'topology_ms=60' "$METRICS_FILE" || { echo "FAIL: native total timing boundary changed" >&2; exit 1; }

cat > "$BIN_DIR/bad_perf_clock" <<'EOF'
#!/bin/bash
printf '08\n'
exit 1
EOF
chmod +x "$BIN_DIR/bad_perf_clock"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_PERF_CLOCK_BIN="$BIN_DIR/bad_perf_clock" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

: > "$LOG_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PERF_CLOCK_BIN="$BIN_DIR/perf_clock" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
[ "$(wc -l < "$CLOCK_LOG" | tr -d ' ')" = "6" ] || {
  echo "FAIL: Lua-only spaces must not execute the compiled clock" >&2
  exit 1
}
grep -Fq "click_script=/usr/bin/env BARISTA_LUA_ONLY=1 $CONFIG_DIR/scripts/space_action.sh focus --space 1" "$LOG_FILE" || {
  echo "FAIL: Lua-only space clicks must preserve the helper gate" >&2
  exit 1
}
grep -Fq "click_script=/usr/bin/env BARISTA_LUA_ONLY=1 $CONFIG_DIR/scripts/space_action.sh create --display 1" "$LOG_FILE" || {
  echo "FAIL: Lua-only creator clicks must preserve the helper gate" >&2
  exit 1
}

mkdir -p "$CONFIG_DIR/bin"
cat > "$CONFIG_DIR/bin/space_manager" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$CONFIG_DIR/bin/space_manager"
chmod -x "$CONFIG_DIR/scripts/space_action.sh"
: > "$LOG_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PERF_CLOCK_BIN="$BIN_DIR/perf_clock" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
if grep -Fq "click_script=$CONFIG_DIR/bin/space_manager create" "$LOG_FILE"; then
  echo "FAIL: Lua-only creator fallback must ignore a leftover compiled manager" >&2
  exit 1
fi
grep -Fq "click_script=yabai -m space --create" "$LOG_FILE" || {
  echo "FAIL: Lua-only creator fallback should retain the portable yabai action" >&2
  exit 1
}

printf 'test_simple_spaces_full_rebuild.sh: ok\n'
