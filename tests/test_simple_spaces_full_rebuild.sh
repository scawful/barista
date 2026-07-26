#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/simple_spaces.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
QUERY_LOG="$TMP_DIR/sketchybar-query.log"
JQ_LOG="$TMP_DIR/jq.log"
MUTATION_COUNT_FILE="$TMP_DIR/sketchybar-mutation-count"
MUTATION_RETRY_MARKER_LOG="$TMP_DIR/sketchybar-mutation-retry-markers"
STATE_JQ_COUNT_FILE="$TMP_DIR/state-jq-count"
METRICS_FILE="$TMP_DIR/space_metrics.env"
CLOCK_LOG="$TMP_DIR/perf_clock.log"
REAL_JQ="$(command -v jq)"

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

cat > "$BIN_DIR/jq" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$JQ_LOG"
case " \$* " in
  *" $CONFIG_DIR/state.json "*)
    printf 'call\n' >> "$STATE_JQ_COUNT_FILE"
    if [ "\${BARISTA_TEST_FAIL_STATE_ONCE:-0}" = "1" ] \
      && [ "\$(wc -l < "$STATE_JQ_COUNT_FILE" | tr -d ' ')" = "1" ]; then
      exit 1
    fi
    ;;
esac
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$BIN_DIR/jq"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "bar" ]; then
  printf '%s\n' "\$*" >> "$QUERY_LOG"
  if [ "\${BARISTA_TEST_INVALID_BAR_ONCE:-0}" = "1" ] && [ "\$(wc -l < "$QUERY_LOG" | tr -d ' ')" = "1" ]; then
    printf '{\n'
    exit 0
  fi
  if [ "\${BARISTA_TEST_STALE_BAR:-0}" = "1" ]; then
    printf '{"height":28,"items":["front_app","front_app_divider","space.99","space_creator.9"]}\n'
    exit 0
  fi
  printf '{"height":28,"items":["front_app","front_app_divider"]}\n'
  exit 0
fi
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "front_app" ]; then
  printf '{}\n'
  exit 0
fi
printf '%s\n' "\$*" >> "\$LOG_FILE"
printf 'call\n' >> "$MUTATION_COUNT_FILE"
printf '%s\n' "\${BARISTA_TOPOLOGY_APPLY_RETRY:-0}" >> "$MUTATION_RETRY_MARKER_LOG"
if [ "\${BARISTA_TEST_FAIL_COMBINED_ONCE:-0}" = "1" ] \
  && [ "\${1:-}" = "--remove" ] \
  && [ "\$(wc -l < "$MUTATION_COUNT_FILE" | tr -d ' ')" = "1" ]; then
  exit 1
fi
if [ "\${BARISTA_TEST_FAIL_ALL_MUTATIONS:-0}" = "1" ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

if ! grep -Fq -- "--add space space.1" "$LOG_FILE"; then
  echo "FAIL: empty bar snapshot should force full rebuild and add space.1" >&2
  exit 1
fi

if [ "$(wc -l < "$QUERY_LOG" | tr -d ' ')" != "1" ]; then
  echo "FAIL: full rebuild should reuse one bar snapshot for height, membership, and anchors" >&2
  exit 1
fi

if [ "$(grep -Fc -- "$CONFIG_DIR/state.json" "$JQ_LOG")" != "1" ]; then
  echo "FAIL: full rebuild should parse space configuration from state.json once" >&2
  exit 1
fi

if [ "$(wc -l < "$LOG_FILE" | tr -d ' ')" != "1" ]; then
  echo "FAIL: full rebuild should remove and reconstruct topology in one SketchyBar request" >&2
  exit 1
fi

if ! grep -Fq -- "--remove /space\\..*/" "$LOG_FILE"; then
  echo "FAIL: full rebuild request should remove stale space items" >&2
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

: > "$CLOCK_LOG"
: > "$LOG_FILE"
: > "$QUERY_LOG"
: > "$MUTATION_COUNT_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_TEST_INVALID_BAR_ONCE=1 \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
if [ "$(wc -l < "$QUERY_LOG" | tr -d ' ')" != "2" ]; then
  echo "FAIL: an invalid bar snapshot should receive one parent-shell retry" >&2
  exit 1
fi
grep -Fq -- "--add space space.1" "$LOG_FILE" || {
  echo "FAIL: a valid retry should still reconstruct the topology" >&2
  exit 1
}

: > "$CLOCK_LOG"
: > "$LOG_FILE"
: > "$QUERY_LOG"
: > "$MUTATION_COUNT_FILE"
: > "$STATE_JQ_COUNT_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_TEST_FAIL_STATE_ONCE=1 \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
if [ "$(wc -l < "$STATE_JQ_COUNT_FILE" | tr -d ' ')" != "2" ]; then
  echo "FAIL: a failed state parse should receive one parent-shell retry" >&2
  exit 1
fi
grep -Fq -- "--add item space_creator " "$LOG_FILE" || {
  echo "FAIL: a successful state retry should preserve creator_mode=primary" >&2
  exit 1
}
if grep -Fq -- "--add item space_creator.1 " "$LOG_FILE"; then
  echo "FAIL: a transient state parse failure must not freeze the default creator mode" >&2
  exit 1
fi

: > "$CLOCK_LOG"
: > "$LOG_FILE"
: > "$QUERY_LOG"
: > "$MUTATION_COUNT_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_TEST_STALE_BAR=1 \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
stale_request="$(sed -n '1p' "$LOG_FILE")"
case "$stale_request" in
  *"--remove /space\\..*/"*"--add space space.1"*) ;;
  *)
    echo "FAIL: stale topology removal should precede reconstruction in one request" >&2
    exit 1
    ;;
esac
grep -Fxq 'removed=1' "$METRICS_FILE" || {
  echo "FAIL: stale full rebuild should report the removed space item" >&2
  exit 1
}

: > "$CLOCK_LOG"
: > "$LOG_FILE"
: > "$QUERY_LOG"
: > "$MUTATION_COUNT_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_TEST_FAIL_COMBINED_ONCE=1 \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
if [ "$(wc -l < "$LOG_FILE" | tr -d ' ')" != "3" ]; then
  echo "FAIL: a failed combined request should clean partial state before one reconstruction attempt" >&2
  exit 1
fi
if ! sed -n '2p' "$LOG_FILE" | grep -Fq -- "--remove"; then
  echo "FAIL: combined-request recovery should remove partially applied topology" >&2
  exit 1
fi
if sed -n '2p' "$LOG_FILE" | grep -Fq -- "--add space"; then
  echo "FAIL: combined-request cleanup should not mix another reconstruction payload" >&2
  exit 1
fi
sed -n '3p' "$LOG_FILE" | grep -Fq -- "--add space space.1" || {
  echo "FAIL: combined-request recovery should retain the complete reconstruction payload" >&2
  exit 1
}

: > "$CLOCK_LOG"
: > "$LOG_FILE"
: > "$QUERY_LOG"
: > "$MUTATION_COUNT_FILE"
: > "$MUTATION_RETRY_MARKER_LOG"
if PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_TEST_FAIL_ALL_MUTATIONS=1 \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"; then
  echo "FAIL: an unavailable SketchyBar client should fail the topology apply" >&2
  exit 1
fi
for _ in {1..40}; do
  mutation_count="$(wc -l < "$MUTATION_COUNT_FILE" | tr -d ' ')"
  if [ "$mutation_count" -ge 6 ]; then
    break
  fi
  sleep 0.05
done
if [ "$(wc -l < "$MUTATION_COUNT_FILE" | tr -d ' ')" != "6" ]; then
  echo "FAIL: initial and one repair attempt should each stop after combined, cleanup, and reconstruction failures" >&2
  exit 1
fi
if [ "$(sed -n '1,3p' "$MUTATION_RETRY_MARKER_LOG" | grep -Fxc '0')" != "3" ] \
  || [ "$(sed -n '4,6p' "$MUTATION_RETRY_MARKER_LOG" | grep -Fxc '1')" != "3" ]; then
  echo "FAIL: topology apply repair should run exactly once with its retry marker" >&2
  exit 1
fi

: > "$CLOCK_LOG"
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
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"

: > "$LOG_FILE"
PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PERF_CLOCK_BIN="$BIN_DIR/perf_clock" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
  BARISTA_SPACE_METRICS_FILE="$METRICS_FILE" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT"
[ "$(wc -l < "$CLOCK_LOG" | tr -d ' ')" = "0" ] || {
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
  BARISTA_JQ_BIN="$BIN_DIR/jq" \
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
