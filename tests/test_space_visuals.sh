#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/space_visuals.sh"
STATS_SCRIPT="$ROOT_DIR/bin/barista-stats.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
SCRIPTS_DIR="$TMP_DIR/scripts"
BAR_STATE_DIR="$TMP_DIR/bar_state"
LOG_FILE="$CONFIG_DIR/.barista_stats.log"
YABAI_LOG="$TMP_DIR/yabai.log"
SKETCHYBAR_LOG="$TMP_DIR/sketchybar.log"
HELPER_LOG="$TMP_DIR/space_visual_helper.log"
ICON_LOG="$TMP_DIR/app_icon.log"
CLOCK_LOG="$TMP_DIR/perf_clock.log"
TIMEOUT_BIN="$(command -v timeout || true)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$SCRIPTS_DIR" "$CONFIG_DIR/cache" "$CONFIG_DIR/bin" "$BAR_STATE_DIR"
cp "$STATS_SCRIPT" "$CONFIG_DIR/bin/barista-stats.sh"
chmod +x "$CONFIG_DIR/bin/barista-stats.sh"

CC_BIN="${CC:-$(command -v cc 2>/dev/null || true)}"
[ -n "$CC_BIN" ] || { echo "FAIL: a C compiler is required for the native lock test boundary" >&2; exit 1; }
"$CC_BIN" -std=c99 -Wall -Wextra -Werror "$ROOT_DIR/helpers/file_lock.c" -o "$BIN_DIR/file_lock"

cat > "$BIN_DIR/perf_clock" <<'EOF'
#!/bin/bash
printf 'clock\n' >> "$BARISTA_PERF_CLOCK_LOG"
printf '%s000\n' "$(/bin/date +%s)"
EOF
chmod +x "$BIN_DIR/perf_clock"
export BARISTA_PERF_CLOCK_BIN="$BIN_DIR/perf_clock"
export BARISTA_PERF_CLOCK_LOG="$CLOCK_LOG"

cat > "$CONFIG_DIR/state.json" <<'EOF'
{
  "space_modes": {
    "2": "bsp"
  }
}
EOF

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "__YABAI_LOG__"
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  if [ "${4:-}" = "--space" ]; then
    printf '{"display":1,"index":1,"is-visible":true,"type":"bsp"}\n'
    exit 0
  fi
  printf '[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"has-focus":false,"type":"bsp"},{"display":2,"index":3,"is-visible":true,"has-focus":false,"type":"bsp"}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--windows" ]; then
  if [ "${4:-}" = "--space" ]; then
    if [ "${5:-}" = "1" ]; then
      printf '[{"space":1,"app":"FocusApp","has-focus":true,"is-minimized":false,"id":10}]\n'
      exit 0
    fi
    if [ "${5:-}" = "3" ]; then
      printf '[{"space":3,"app":"VisibleApp","has-focus":false,"is-minimized":false,"id":11}]\n'
      exit 0
    fi
    printf '[]\n'
    exit 0
  fi
  printf '[{"space":1,"app":"FocusApp","has-focus":true,"is-minimized":false,"id":10}]\n'
  exit 0
fi
exit 1
EOF
python3 - <<'PY' "$BIN_DIR/yabai" "$YABAI_LOG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("__YABAI_LOG__", sys.argv[2]), encoding="utf-8")
PY
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
STATE_DIR="__BAR_STATE_DIR__"
if [ "${1:-}" = "--query" ] && [ "${2:-}" = "bar" ]; then
  printf 'query\tbar\n' >> "__SKETCHYBAR_LOG__"
  printf '{"items":["space.1","space.2","space.3"]}\n'
  exit 0
fi
if [ "${1:-}" = "--query" ] && [[ "${2:-}" == space.* ]]; then
  item="${2#space.}"
  icon=""
  [ -f "$STATE_DIR/$item.icon" ] && icon="$(cat "$STATE_DIR/$item.icon")"
  printf '{"icon":{"value":"%s"}}\n' "$icon"
  exit 0
fi

printf 'set\t%s\n' "$*" >> "__SKETCHYBAR_LOG__"
if [ "${BARISTA_TEST_SKETCHYBAR_APPLY_FAIL:-0}" = "1" ]; then
  exit 1
fi
current_item=""
while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --set)
      shift
      current_item="${1:-}"
      shift || true
      ;;
    icon=*)
      if [[ "$current_item" == space.* ]]; then
        item="${current_item#space.}"
        printf '%s' "${1#icon=}" > "$STATE_DIR/$item.icon"
      fi
      shift
      ;;
    *)
      shift
      ;;
  esac
done
exit 0
EOF
python3 - <<'PY' "$BIN_DIR/sketchybar" "$BAR_STATE_DIR" "$SKETCHYBAR_LOG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("__BAR_STATE_DIR__", sys.argv[2])
text = text.replace("__SKETCHYBAR_LOG__", sys.argv[3])
path.write_text(text, encoding="utf-8")
PY
chmod +x "$BIN_DIR/sketchybar"

cat > "$SCRIPTS_DIR/app_icon.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "--batch" ]; then
  while IFS= read -r app || [ -n "$app" ]; do
    [ -n "$app" ] || continue
    printf 'batch\t%s\n' "$app" >> "__ICON_LOG__"
    printf '%s\tX\n' "$app"
  done
  exit 0
fi
printf 'single\t%s\n' "${1:-}" >> "__ICON_LOG__"
case "${1:-}" in
  WaiterA) printf 'A' ;;
  WaiterB) printf 'B' ;;
  *) printf 'X' ;;
esac
EOF
python3 - <<'PY' "$SCRIPTS_DIR/app_icon.sh" "$ICON_LOG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("__ICON_LOG__", sys.argv[2]), encoding="utf-8")
PY
chmod +x "$SCRIPTS_DIR/app_icon.sh"

cat > "$BIN_DIR/space_visual_helper" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'helper\t%s\n' "$*" >> "__HELPER_LOG__"
[ "${1:-}" = "visible-apps" ] || exit 64
shift
for space_index in "$@"; do
  case "$space_index" in
    1) printf '1\tFocusApp\n' ;;
    3) printf '3\tVisibleApp\n' ;;
  esac
done
EOF
python3 - <<'PY' "$BIN_DIR/space_visual_helper" "$HELPER_LOG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("__HELPER_LOG__", sys.argv[2]), encoding="utf-8")
PY
chmod +x "$BIN_DIR/space_visual_helper"

cat > "$SCRIPTS_DIR/front_app_context.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
app="${BARISTA_TEST_FOCUSED_APP:-FocusApp}"
space="${BARISTA_TEST_FOCUSED_SPACE:-1}"
display="${BARISTA_TEST_FOCUSED_DISPLAY:-1}"
visible="${BARISTA_TEST_FOCUSED_VISIBLE:-true}"
if [ -n "${BARISTA_TEST_CURRENT_FOCUS_FILE:-}" ] && [ -f "$BARISTA_TEST_CURRENT_FOCUS_FILE" ]; then
  IFS=$'\t' read -r app space display visible < "$BARISTA_TEST_CURRENT_FOCUS_FILE"
fi
if [ -n "${BARISTA_TEST_CONTEXT_ENTER_FILE:-}" ]; then
  : > "$BARISTA_TEST_CONTEXT_ENTER_FILE"
fi
if [ -n "${BARISTA_TEST_CONTEXT_DELAY:-}" ]; then
  sleep "$BARISTA_TEST_CONTEXT_DELAY"
fi
printf 'app_name\t%s\n' "$app"
printf 'space_index\t%s\n' "$space"
printf 'display_index\t%s\n' "$display"
printf 'space_visible\t%s\n' "$visible"
EOF
chmod +x "$SCRIPTS_DIR/front_app_context.sh"

cat > "$BIN_DIR/failing_mv" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$BIN_DIR/failing_mv"

cat > "$BIN_DIR/legacy_lockf" <<'EOF'
#!/bin/bash
# macOS 13/14 reject the newer file-descriptor/no-command lockf form.
exit 64
EOF
chmod +x "$BIN_DIR/legacy_lockf"

run_visual() {
  local sender="$1"
  shift
  local -a cmd=(
    env
    PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar"
    BARISTA_YABAI_BIN="$BIN_DIR/yabai"
    BARISTA_SPACE_VISUAL_HELPER_BIN="$BIN_DIR/space_visual_helper"
    BARISTA_FILE_LOCK_BIN="$BIN_DIR/file_lock"
    BARISTA_FLOCK_BIN="$BIN_DIR/missing_flock"
    BARISTA_LOCKF_BIN="$BIN_DIR/legacy_lockf"
    CONFIG_DIR="$CONFIG_DIR"
    SCRIPTS_DIR="$SCRIPTS_DIR"
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh"
    BARISTA_SPACE_VISUAL_PHASE_METRICS=1
    STATE_FILE="$CONFIG_DIR/state.json"
    SENDER="$sender"
  )
  while [ "$#" -gt 0 ]; do
    cmd+=("$1")
    shift
  done
  cmd+=("$SCRIPT")
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 5 "${cmd[@]}"
    return $?
  fi
  "${cmd[@]}"
}

count_visual_events() {
  if [ ! -f "$LOG_FILE" ]; then
    echo 0
    return
  fi
  jq -sr '[.[] | select(.event == "space_visual_refresh")] | length' "$LOG_FILE"
}

latest_visual_path() {
  jq -sr '[.[] | select(.event == "space_visual_refresh")][-1].path // ""' "$LOG_FILE"
}

count_yabai_line() {
  local line="$1"
  if [ ! -f "$YABAI_LOG" ]; then
    echo 0
    return
  fi
  grep -Fxc -- "$line" "$YABAI_LOG" 2>/dev/null || true
}

count_sketchybar_line() {
  local line="$1"
  if [ ! -f "$SKETCHYBAR_LOG" ]; then
    echo 0
    return
  fi
  grep -Fxc -- "$line" "$SKETCHYBAR_LOG" 2>/dev/null || true
}

count_helper_line() {
  local line="$1"
  if [ ! -f "$HELPER_LOG" ]; then
    echo 0
    return
  fi
  grep -Fxc -- "$line" "$HELPER_LOG" 2>/dev/null || true
}

count_icon_line() {
  local line="$1"
  if [ ! -f "$ICON_LOG" ]; then
    echo 0
    return
  fi
  grep -Fxc -- "$line" "$ICON_LOG" 2>/dev/null || true
}

start_test_lock_holder() {
  local lock_file="$1"
  local ready_file="$2"
  local hold_seconds="${3:-1}"
  local attempts=100
  rm -f "$ready_file"
  /bin/bash -c '
    set -e
    exec 9>"$1"
    "$4" 9
    : > "$2"
    sleep "$3"
  ' _ "$lock_file" "$ready_file" "$hold_seconds" "$BIN_DIR/file_lock" &
  TEST_LOCK_HOLDER_PID=$!
  while [ ! -e "$ready_file" ] && [ "$attempts" -gt 0 ]; do
    kill -0 "$TEST_LOCK_HOLDER_PID" >/dev/null 2>&1 || break
    sleep 0.01
    attempts=$((attempts - 1))
  done
  [ -e "$ready_file" ]
}

test_lock_available() {
  /bin/bash -c '
    exec 9>"$1"
    "$2" 9 >/dev/null 2>&1
  ' _ "$1" "$BIN_DIR/file_lock"
}

run_visual "manual"
[ "$(count_visual_events)" = "1" ] || { echo "FAIL: manual refresh should log exactly one event" >&2; exit 1; }
jq -e -s '
  [.[] | select(.event == "space_visual_refresh")][0]
  | .path == "full"
    and (.spaces_ms >= 0)
    and (.lookup_ms >= 0)
    and (.state_ms >= 0)
    and (.loop_ms >= 0)
    and (.app_ms >= 0)
    and (.glyph_ms >= 0)
    and (.style_ms >= 0)
    and (.apply_ms >= 0)
    and (.style_writes >= 3)
' "$LOG_FILE" >/dev/null || { echo "FAIL: visual refresh event should include phase timing metadata" >&2; exit 1; }
[ "$("$BIN_DIR/sketchybar" --query space.2 | jq -r '.icon.value')" != "bsp" ] || { echo "FAIL: space_modes must not leak into space icons" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "0" ] || { echo "FAIL: authoritative refresh should derive the space-item cache from the spaces payload without querying the full bar" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: authoritative refresh should not query the full windows snapshot" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows --space 1")" = "0" ] || { echo "FAIL: helper-backed authoritative refresh should not use the shell scoped window query for focused spaces" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows --space 3")" = "0" ] || { echo "FAIL: helper-backed authoritative refresh should not use the shell scoped window query for inactive visible spaces" >&2; exit 1; }
[ "$(count_helper_line $'helper\tvisible-apps 1 3')" = "1" ] || { echo "FAIL: authoritative refresh should batch visible-space app lookup through the helper" >&2; exit 1; }
[ "$(count_icon_line $'batch\tFocusApp')" = "1" ] || { echo "FAIL: focused app glyph should be resolved through one batch icon helper call" >&2; exit 1; }
[ "$(count_icon_line $'batch\tVisibleApp')" = "1" ] || { echo "FAIL: visible app glyph should be resolved through one batch icon helper call" >&2; exit 1; }
grep -Fq -- 'space.1 icon=X label.drawing=off background.drawing=on background.color=0xffd8c4ff background.border_width=2 background.border_color=0xffffffff icon.color=0xff11111b' "$SKETCHYBAR_LOG" || {
  echo "FAIL: focused space should get the filled active pill with border" >&2
  exit 1
}
grep -Fq -- 'space.3 icon=X label.drawing=off background.drawing=on background.color=0x3a313a46 background.border_width=1 background.border_color=0x66d8c4ff icon.color=0xffcdd6f4' "$SKETCHYBAR_LOG" || {
  echo "FAIL: visible inactive space should get the stronger dark pill with subtle border" >&2
  exit 1
}
grep -Fq -- 'space.2 icon=○ label.drawing=off background.drawing=on background.color=0x18313a46 background.border_width=0 background.border_color=0x00000000 icon.color=0xffbac2de' "$SKETCHYBAR_LOG" || {
  echo "FAIL: hidden idle space should keep the dark chip style" >&2
  exit 1
}
[ -f "$CONFIG_DIR/cache/space_visuals/style_state/space.1.state" ] || { echo "FAIL: focused style state should be persisted" >&2; exit 1; }
[ -f "$CONFIG_DIR/cache/space_visuals/style_state/space.3.state" ] || { echo "FAIL: visible style state should be persisted" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: full refresh should atomically persist focused space and display" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_selected_space" ] || { echo "FAIL: successful context publication should retire the legacy space-only marker" >&2; exit 1; }

: > "$YABAI_LOG"
run_visual "manual" \
  BARISTA_SPACE_VISUAL_HELPER_BIN="$TMP_DIR/missing_space_visual_helper"
[ "$(count_yabai_line "-m query --windows --space 1")" = "1" ] || { echo "FAIL: missing helper should fall back to the focused scoped window query" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows --space 3")" = "1" ] || { echo "FAIL: missing helper should fall back to inactive scoped window queries" >&2; exit 1; }

: > "$YABAI_LOG"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  INFO="FocusApp"
[ "$(count_visual_events)" = "3" ] || { echo "FAIL: focused front_app refresh should be recorded" >&2; exit 1; }
[ "$(count_yabai_line "-m query --spaces --space")" = "0" ] || { echo "FAIL: focused front_app refresh should not query the focused space directly when the helper provides it" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: focused front_app refresh should not query all windows" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "0" ] || { echo "FAIL: focused front_app refresh should reuse cached space-item lookup instead of querying the full bar" >&2; exit 1; }

: > "$YABAI_LOG"
run_visual "space_active_refresh" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: focused active-space refresh should be recorded" >&2; exit 1; }
[ "$(count_yabai_line "-m query --spaces")" = "0" ] || { echo "FAIL: focused active-space refresh should not query all spaces" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: focused active-space refresh should not query all windows" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "0" ] || { echo "FAIL: focused active-space refresh should reuse cached space-item lookup instead of querying the full bar" >&2; exit 1; }

run_visual "forced"
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: forced script runs should be ignored because explicit refresh paths already exist" >&2; exit 1; }

rm -f "$CONFIG_DIR/cache/space_visuals/last_front_app_refresh_ms" "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
start_test_lock_holder "$CONFIG_DIR/cache/space_visuals/visual.lock" "$TMP_DIR/manual_lock_ready" 0.30 || {
  echo "FAIL: unable to hold the visual lock for the contention smoke test" >&2
  exit 1
}
manual_lock_holder_pid="$TEST_LOCK_HOLDER_PID"
run_visual "manual"
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: locked refresh should not add a visual event" >&2; exit 1; }
wait "$manual_lock_holder_pid"

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000
[ "$(count_visual_events)" = "5" ] || { echo "FAIL: first front_app_switched should be recorded when cooldown is disabled" >&2; exit 1; }

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000
[ "$(count_visual_events)" = "5" ] || { echo "FAIL: front_app debounce should suppress the second rapid refresh" >&2; exit 1; }

run_visual "space_topology_refresh" \
  BARISTA_ALL_SPACES_DATA='[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"has-focus":false,"type":"bsp"}]' \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "6" ] || { echo "FAIL: topology refresh should be recorded" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "0" ] || { echo "FAIL: topology refresh with shared spaces payload should reuse the topology item set instead of querying the full bar again" >&2; exit 1; }

run_visual "startup_sync" \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "6" ] || { echo "FAIL: startup_sync should be skipped when a recent authoritative topology refresh already ran" >&2; exit 1; }

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "6" ] || { echo "FAIL: cooldown should suppress front_app refresh after topology refresh" >&2; exit 1; }
[ -s "$CLOCK_LOG" ] || { echo "FAIL: visual refresh should prefer the injected native clock" >&2; exit 1; }

printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
run_visual "startup_sync" \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_ATTEMPTS=100 \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_DELAY=0.01 \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=5000 &
startup_wait_pid=$!
sleep 0.10
kill -0 "$startup_wait_pid" >/dev/null 2>&1 || { echo "FAIL: startup_sync should remain blocked while active topology owns its lock" >&2; exit 1; }
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
wait "$startup_wait_pid"
[ "$(count_visual_events)" = "6" ] || { echo "FAIL: startup_sync should wait for an active topology visual and then honor its marker" >&2; exit 1; }

printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
run_visual "startup_sync" \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_ATTEMPTS=1 \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_DELAY=0.01 \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=5000
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
[ "$(count_visual_events)" = "7" ] || { echo "FAIL: startup_sync should fail open after a bounded topology wait even when a stale marker exists" >&2; exit 1; }

rm -f "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
topology_started_at="$(python3 - <<'PY'
import time
print(time.monotonic_ns())
PY
)"
run_visual "space_topology_refresh" \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_ATTEMPTS=20 \
  BARISTA_SPACE_STARTUP_TOPOLOGY_WAIT_DELAY=0.10 \
  BARISTA_ALL_SPACES_DATA='[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"has-focus":false,"type":"bsp"}]'
topology_finished_at="$(python3 - <<'PY'
import time
print(time.monotonic_ns())
PY
)"
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
topology_elapsed_ms=$(((topology_finished_at - topology_started_at) / 1000000))
[ "$topology_elapsed_ms" -lt 1500 ] || { echo "FAIL: topology refresh waited on its own lock (${topology_elapsed_ms}ms)" >&2; exit 1; }
[ "$(count_visual_events)" = "8" ] || { echo "FAIL: topology refresh should not wait on its own orchestration lock" >&2; exit 1; }

printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
run_visual "space_topology_refresh" \
  BARISTA_YABAI_BIN="$TMP_DIR/missing_yabai"
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: failed topology discovery must invalidate the prior authoritative marker" >&2; exit 1; }
[ "$(count_visual_events)" = "8" ] || { echo "FAIL: failed topology discovery should not record a visual event" >&2; exit 1; }

run_visual "startup_sync" \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=5000
[ "$(count_visual_events)" = "9" ] || { echo "FAIL: startup_sync should recover after failed topology discovery" >&2; exit 1; }

printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
set +e
run_visual "space_topology_refresh" \
  BARISTA_TEST_SKETCHYBAR_APPLY_FAIL=1 \
  BARISTA_ALL_SPACES_DATA='[{"display":1,"index":1,"is-visible":true,"has-focus":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"has-focus":false,"type":"bsp"}]'
failed_apply_status=$?
set -e
[ "$failed_apply_status" -ne 0 ] || { echo "FAIL: failed SketchyBar apply should propagate failure" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: failed SketchyBar apply must invalidate the prior authoritative marker" >&2; exit 1; }
[ "$(count_visual_events)" = "9" ] || { echo "FAIL: failed SketchyBar apply should not record a visual event" >&2; exit 1; }
[ -z "$(find "$CONFIG_DIR/cache/space_visuals/style_state" -maxdepth 1 -name 'space.*.state' -print -quit 2>/dev/null)" ] || { echo "FAIL: failed apply should invalidate staged style state" >&2; exit 1; }

run_visual "startup_sync" \
  BARISTA_SPACE_STARTUP_SYNC_COOLDOWN_MS=5000
[ "$(count_visual_events)" = "10" ] || { echo "FAIL: startup_sync should recover after a failed SketchyBar apply" >&2; exit 1; }

# A same-display focus move hides the previous space, so it must become idle.
: > "$SKETCHYBAR_LOG"
run_visual "space_active_refresh" \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
[ "$(count_visual_events)" = "11" ] || { echo "FAIL: same-display focused refresh should be recorded" >&2; exit 1; }
[ "$(latest_visual_path)" = "focus" ] || { echo "FAIL: valid selected context should retain the focused fast path" >&2; exit 1; }
grep -Fq -- '--set space.1 label.drawing=off background.drawing=on background.color=0x18313a46 background.border_width=0 background.border_color=0x00000000 icon.color=0xffbac2de --set space.2 icon=X' "$SKETCHYBAR_LOG" || {
  echo "FAIL: same-display transition should batch previous-idle and current-focused styles" >&2
  exit 1
}
[ "$(head -n 1 "$CONFIG_DIR/cache/space_visuals/style_state/space.1.state")" = "state=idle" ] || { echo "FAIL: same-display previous space should persist idle restore state" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t2\t1' ] || { echo "FAIL: same-display transition should advance the selected context" >&2; exit 1; }

# A cross-display focus move leaves the previous display's space visible.
: > "$SKETCHYBAR_LOG"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_TEST_FOCUSED_APP="VisibleApp" \
  BARISTA_TEST_FOCUSED_SPACE=3 \
  BARISTA_TEST_FOCUSED_DISPLAY=2 \
  INFO="VisibleApp"
[ "$(count_visual_events)" = "12" ] || { echo "FAIL: cross-display focused refresh should be recorded" >&2; exit 1; }
[ "$(latest_visual_path)" = "focus" ] || { echo "FAIL: cross-display transition should stay on the focused path" >&2; exit 1; }
grep -Fq -- '--set space.2 label.drawing=off background.drawing=on background.color=0x3a313a46 background.border_width=1 background.border_color=0x66d8c4ff icon.color=0xffcdd6f4 --set space.3 icon=X' "$SKETCHYBAR_LOG" || {
  echo "FAIL: cross-display transition should batch previous-visible and current-focused styles" >&2
  exit 1
}
[ "$(head -n 1 "$CONFIG_DIR/cache/space_visuals/style_state/space.2.state")" = "state=visible" ] || { echo "FAIL: cross-display previous space should persist visible restore state" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t3\t2' ] || { echo "FAIL: cross-display transition should atomically advance space and display" >&2; exit 1; }
cp "$CONFIG_DIR/cache/space_visuals/style_state/space.2.state" "$TMP_DIR/cross_display_space_2.state"

env \
  PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_HOVER_STATE_DIR="$TMP_DIR/hover" \
  CONFIG_DIR="$CONFIG_DIR" \
  NAME="space.2" \
  SENDER="mouse.exited" \
  "$ROOT_DIR/plugins/space.sh"
grep -Fq -- 'space.2 label.drawing=off background.drawing=on background.color=0x3a313a46 background.border_width=1 background.border_color=0x66d8c4ff icon.color=0xffcdd6f4' "$SKETCHYBAR_LOG" || {
  echo "FAIL: hover exit should restore the cross-display visible state" >&2
  exit 1
}

# The full visual path is the correctness oracle for the same two-display state.
run_visual "space_topology_refresh" \
  BARISTA_ALL_SPACES_DATA='[{"display":1,"index":1,"is-visible":false,"has-focus":false,"type":"bsp"},{"display":1,"index":2,"is-visible":true,"has-focus":false,"type":"bsp"},{"display":2,"index":3,"is-visible":true,"has-focus":true,"type":"bsp"}]'
[ "$(count_visual_events)" = "13" ] || { echo "FAIL: cross-display oracle refresh should be recorded" >&2; exit 1; }
[ "$(latest_visual_path)" = "full" ] || { echo "FAIL: cross-display oracle should use the full path" >&2; exit 1; }
cmp -s "$TMP_DIR/cross_display_space_2.state" "$CONFIG_DIR/cache/space_visuals/style_state/space.2.state" || {
  echo "FAIL: focused cross-display restore state should match the full-path oracle" >&2
  exit 1
}

# Front-app refreshes wait outside the visual lock and then apply the latest event.
context_before_topology="$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")"
: > "$SKETCHYBAR_LOG"
rm -f "$CONFIG_DIR/cache/space_visuals/last_front_app_refresh_ms"
focus_state_file="$TMP_DIR/current_focus.tsv"
printf 'WaiterA\t1\t1\ttrue\n' > "$focus_state_file"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS=100 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_DELAY=0.01 \
  BARISTA_SPACE_FRONT_APP_VISUAL_WAIT_ATTEMPTS=0 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$focus_state_file" \
  INFO="WaiterA" &
front_app_wait_a_pid=$!
sleep 0.03
printf 'WaiterB\t1\t1\ttrue\n' > "$focus_state_file"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS=100 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_DELAY=0.01 \
  BARISTA_SPACE_FRONT_APP_VISUAL_WAIT_ATTEMPTS=0 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$focus_state_file" \
  INFO="WaiterB" &
front_app_wait_b_pid=$!
sleep 0.10
kill -0 "$front_app_wait_a_pid" >/dev/null 2>&1 || { echo "FAIL: first front-app refresh should wait while topology owns its lock" >&2; exit 1; }
kill -0 "$front_app_wait_b_pid" >/dev/null 2>&1 || { echo "FAIL: latest front-app refresh should wait while topology owns its lock" >&2; exit 1; }
[ "$(count_visual_events)" = "13" ] || { echo "FAIL: waiting front-app refresh should not publish early" >&2; exit 1; }
[ ! -s "$SKETCHYBAR_LOG" ] || { echo "FAIL: waiting front-app refresh should not mutate SketchyBar early" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = "$context_before_topology" ] || { echo "FAIL: waiting front-app refresh should not advance selected context early" >&2; exit 1; }
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
wait "$front_app_wait_a_pid"
wait "$front_app_wait_b_pid"
[ "$(count_visual_events)" = "14" ] || { echo "FAIL: front-app refresh should converge after topology releases its lock" >&2; exit 1; }
[ "$(latest_visual_path)" = "focus" ] || { echo "FAIL: post-topology front-app convergence should retain the focused path" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: post-topology front-app convergence should advance selected context" >&2; exit 1; }
grep -Fq -- '--set space.1 icon=B' "$SKETCHYBAR_LOG" || { echo "FAIL: topology waiters should converge on the newest focused app" >&2; exit 1; }

# A stale topology lock fails open after the configured bound instead of dropping events.
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_ATTEMPTS=1 \
  BARISTA_SPACE_FRONT_APP_TOPOLOGY_WAIT_DELAY=0.01 \
  BARISTA_TEST_FOCUSED_APP="VisibleApp" \
  BARISTA_TEST_FOCUSED_SPACE=3 \
  BARISTA_TEST_FOCUSED_DISPLAY=2 \
  INFO="VisibleApp"
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
[ "$(count_visual_events)" = "15" ] || { echo "FAIL: stale topology lock should fail open to the latest front-app refresh" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t3\t2' ] || { echo "FAIL: stale-lock recovery should advance selected context" >&2; exit 1; }

# refresh_spaces intentionally invokes active refresh while holding this lock.
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
run_visual "space_active_refresh" \
  BARISTA_TEST_FOCUSED_SPACE=1 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
[ "$(count_visual_events)" = "16" ] || { echo "FAIL: active-space refresh must still execute under the topology lock" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: topology-owned active refresh should advance selected context" >&2; exit 1; }

# Reload removes the previous generation before any early active-space event.
rm -f \
  "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" \
  "$CONFIG_DIR/cache/space_visuals/last_selected_context" \
  "$CONFIG_DIR/cache/space_visuals/last_selected_space"
run_visual "space_active_refresh" \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
[ "$(count_visual_events)" = "17" ] || { echo "FAIL: early post-reload active refresh should recover through a full pass" >&2; exit 1; }
[ "$(latest_visual_path)" = "full" ] || { echo "FAIL: early post-reload active refresh must not reuse a prior selection generation" >&2; exit 1; }
[ -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: successful early full recovery should publish authoritative state" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: early full recovery should publish this runtime's selected context" >&2; exit 1; }

# Legacy space-only state is ambiguous and must fail closed to the full oracle.
rm -f "$CONFIG_DIR/cache/space_visuals/last_selected_context"
printf '3' > "$CONFIG_DIR/cache/space_visuals/last_selected_space"
: > "$SKETCHYBAR_LOG"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_TEST_FOCUSED_SPACE=1 \
  BARISTA_TEST_FOCUSED_DISPLAY=1 \
  INFO="FocusApp"
[ "$(count_visual_events)" = "18" ] || { echo "FAIL: legacy selected state should recover through one full refresh" >&2; exit 1; }
[ "$(latest_visual_path)" = "full" ] || { echo "FAIL: legacy selected state must not guess on the focused path" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: full recovery should publish versioned selected context" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_selected_space" ] || { echo "FAIL: full recovery should remove the legacy selected marker" >&2; exit 1; }

# Malformed empty/extra TSV fields must not collapse into a valid generation.
printf 'v1\t\t1\t1\n' > "$CONFIG_DIR/cache/space_visuals/last_selected_context"
: > "$SKETCHYBAR_LOG"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1 \
  INFO="SameDisplayApp"
[ "$(count_visual_events)" = "19" ] || { echo "FAIL: malformed selected context should recover through one full refresh" >&2; exit 1; }
[ "$(latest_visual_path)" = "full" ] || { echo "FAIL: malformed selected context must not enter the focused apply" >&2; exit 1; }
[ "$(wc -l < "$SKETCHYBAR_LOG" | tr -d ' ')" = "1" ] || { echo "FAIL: malformed context should produce only the full-path SketchyBar batch" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: malformed-context recovery should republish a valid generation" >&2; exit 1; }

# A failed atomic context publication must not publish authoritative success.
printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
: > "$SKETCHYBAR_LOG"
set +e
run_visual "space_active_refresh" \
  BARISTA_MV_BIN="$BIN_DIR/failing_mv" \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
failed_context_status=$?
set -e
[ "$failed_context_status" -ne 0 ] || { echo "FAIL: selected-context publication failure should propagate" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_selected_context" ] || { echo "FAIL: failed selected-context publication should invalidate the old generation" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: failed selected-context publication must leave the authoritative marker absent" >&2; exit 1; }
[ -z "$(find "$CONFIG_DIR/cache/space_visuals/style_state" -maxdepth 1 -name 'space.*.state' -print -quit 2>/dev/null)" ] || { echo "FAIL: failed selected-context publication should invalidate staged style state" >&2; exit 1; }
[ "$(count_visual_events)" = "19" ] || { echo "FAIL: failed selected-context publication should not record success" >&2; exit 1; }

run_visual "manual"
[ "$(count_visual_events)" = "20" ] || { echo "FAIL: full refresh should recover after selected-context publication failure" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: recovery should restore selected context" >&2; exit 1; }

# A focused batch failure also invalidates selection/style state and recovers.
printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
set +e
run_visual "space_active_refresh" \
  BARISTA_TEST_SKETCHYBAR_APPLY_FAIL=1 \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
failed_focused_apply_status=$?
set -e
[ "$failed_focused_apply_status" -ne 0 ] || { echo "FAIL: focused SketchyBar batch failure should propagate" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_selected_context" ] || { echo "FAIL: focused apply failure should invalidate selected context" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: focused apply failure should leave the authoritative marker absent" >&2; exit 1; }
[ -z "$(find "$CONFIG_DIR/cache/space_visuals/style_state" -maxdepth 1 -name 'space.*.state' -print -quit 2>/dev/null)" ] || { echo "FAIL: focused apply failure should invalidate staged style state" >&2; exit 1; }
[ "$(count_visual_events)" = "20" ] || { echo "FAIL: focused apply failure should not record success" >&2; exit 1; }

run_visual "manual"
[ "$(count_visual_events)" = "21" ] || { echo "FAIL: full refresh should recover after focused apply failure" >&2; exit 1; }

# Front-app failures must also invalidate an older authoritative marker.
printf '%s000' "$(/bin/date +%s)" > "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
set +e
run_visual "front_app_switched" \
  BARISTA_TEST_SKETCHYBAR_APPLY_FAIL=1 \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_TEST_FOCUSED_APP="SameDisplayApp" \
  BARISTA_TEST_FOCUSED_SPACE=2 \
  BARISTA_TEST_FOCUSED_DISPLAY=1 \
  INFO="SameDisplayApp"
failed_front_app_status=$?
set -e
[ "$failed_front_app_status" -ne 0 ] || { echo "FAIL: failed front-app focused/full apply should propagate" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms" ] || { echo "FAIL: front-app failure should invalidate the older authoritative marker" >&2; exit 1; }
[ ! -e "$CONFIG_DIR/cache/space_visuals/last_selected_context" ] || { echo "FAIL: front-app failure should invalidate selected context" >&2; exit 1; }
[ "$(count_visual_events)" = "21" ] || { echo "FAIL: front-app failure should not record success" >&2; exit 1; }

run_visual "manual"
[ "$(count_visual_events)" = "22" ] || { echo "FAIL: full refresh should recover after front-app failure" >&2; exit 1; }

# Unterminated trailing bytes must not be accepted as a valid context record.
printf 'v1\t1\t1\njunk' > "$CONFIG_DIR/cache/space_visuals/last_selected_context"
: > "$SKETCHYBAR_LOG"
run_visual "space_active_refresh" \
  BARISTA_TEST_FOCUSED_APP="FocusApp" \
  BARISTA_TEST_FOCUSED_SPACE=1 \
  BARISTA_TEST_FOCUSED_DISPLAY=1
[ "$(count_visual_events)" = "23" ] || { echo "FAIL: context with unterminated trailing data should recover through one full refresh" >&2; exit 1; }
[ "$(latest_visual_path)" = "full" ] || { echo "FAIL: unterminated trailing context data must fail closed to the full path" >&2; exit 1; }
[ "$(cat "$CONFIG_DIR/cache/space_visuals/last_selected_context")" = $'v1\t1\t1' ] || { echo "FAIL: trailing-data recovery should republish a valid context" >&2; exit 1; }

# A visual-lock loser waits beyond the former one-second bound, refreshes live
# context, and releases its retry slot before sampling so a still-newer event
# can queue behind it. The sequence must converge A -> B -> A.
: > "$SKETCHYBAR_LOG"
rm -f "$CONFIG_DIR/cache/space_visuals/last_front_app_refresh_ms"
visual_focus_file="$TMP_DIR/visual_lock_focus.tsv"
visual_owner_enter_file="$TMP_DIR/visual_owner_context_entered"
visual_waiter_enter_file="$TMP_DIR/visual_waiter_context_entered"
printf 'WaiterA\t1\t1\ttrue\n' > "$visual_focus_file"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$visual_focus_file" \
  BARISTA_TEST_CONTEXT_ENTER_FILE="$visual_owner_enter_file" \
  BARISTA_TEST_CONTEXT_DELAY=1.20 \
  INFO="WaiterA" &
visual_owner_pid=$!
visual_wait_attempts=100
while [ ! -e "$visual_owner_enter_file" ] && [ "$visual_wait_attempts" -gt 0 ]; do
  sleep 0.01
  visual_wait_attempts=$((visual_wait_attempts - 1))
done
[ -e "$visual_owner_enter_file" ] || { echo "FAIL: delayed visual owner did not enter focused context lookup" >&2; exit 1; }
printf 'WaiterB\t1\t1\ttrue\n' > "$visual_focus_file"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$visual_focus_file" \
  BARISTA_TEST_CONTEXT_ENTER_FILE="$visual_waiter_enter_file" \
  BARISTA_TEST_CONTEXT_DELAY=0.20 \
  INFO="WaiterB" &
visual_waiter_pid=$!
sleep 0.05
kill -0 "$visual_owner_pid" >/dev/null 2>&1 || { echo "FAIL: delayed visual owner should outlive the former one-second retry bound" >&2; exit 1; }
if test_lock_available "$CONFIG_DIR/cache/space_visuals/visual.lock"; then
  echo "FAIL: queued waiter must not unlock the live visual owner" >&2
  exit 1
fi
if test_lock_available "$CONFIG_DIR/cache/space_visuals/front_app_retry.lock"; then
  echo "FAIL: one retry slot should remain held while the waiter is queued" >&2
  exit 1
fi
visual_wait_attempts=300
while [ ! -e "$visual_waiter_enter_file" ] && [ "$visual_wait_attempts" -gt 0 ]; do
  sleep 0.01
  visual_wait_attempts=$((visual_wait_attempts - 1))
done
[ -e "$visual_waiter_enter_file" ] || { echo "FAIL: queued visual waiter did not acquire and sample fresh context" >&2; exit 1; }
printf 'WaiterA\t1\t1\ttrue\n' > "$visual_focus_file"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$visual_focus_file" \
  INFO="WaiterA" &
visual_latest_pid=$!
sleep 0.05
if test_lock_available "$CONFIG_DIR/cache/space_visuals/front_app_retry.lock"; then
  echo "FAIL: newest event should occupy the retry slot while the prior waiter applies" >&2
  exit 1
fi
# An additional event coalesces into the already queued newest refresh.
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000 \
  BARISTA_TEST_CURRENT_FOCUS_FILE="$visual_focus_file" \
  INFO="WaiterA"
wait "$visual_owner_pid"
wait "$visual_waiter_pid"
wait "$visual_latest_pid"
[ "$(count_visual_events)" = "26" ] || { echo "FAIL: A-to-B-to-A contention should apply exactly three ordered refreshes" >&2; exit 1; }
[ "$(latest_visual_path)" = "focus" ] || { echo "FAIL: newest queued refresh should retain the focused path" >&2; exit 1; }
tail -n 1 "$SKETCHYBAR_LOG" | grep -Fq -- '--set space.1 icon=A' || { echo "FAIL: event after the prior waiter's context snapshot must win" >&2; exit 1; }
test_lock_available "$CONFIG_DIR/cache/space_visuals/front_app_retry.lock" || { echo "FAIL: front-app retry lock should be released" >&2; exit 1; }
test_lock_available "$CONFIG_DIR/cache/space_visuals/visual.lock" || { echo "FAIL: visual lock should be released after queued retries" >&2; exit 1; }

# A source checkout on macOS must recover a missing deployed helper before
# taking either visual lock. Other hosts rely on their standard flock CLI.
expected_visual_events=26
if [ "$(uname -s)" = "Darwin" ]; then
  lazy_lock_bin="$TMP_DIR/lazy_file_lock"
  run_visual "manual" \
    BARISTA_FILE_LOCK_BIN="$lazy_lock_bin" \
    BARISTA_FLOCK_BIN="$BIN_DIR/missing_flock" \
    BARISTA_FILE_LOCK_SOURCE="$ROOT_DIR/helpers/file_lock.c" \
    BARISTA_FILE_LOCK_CC="$CC_BIN"
  [ -x "$lazy_lock_bin" ] || { echo "FAIL: missing native lock helper should be built lazily on macOS" >&2; exit 1; }
  expected_visual_events=27
  [ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: lazy native lock build should allow one visual refresh" >&2; exit 1; }
fi

# If no safe lock backend can be established, skip the pass instead of
# creating an ownerless directory lock that a SIGKILL could strand forever.
run_visual "manual" \
  BARISTA_FILE_LOCK_BIN="$TMP_DIR/missing_file_lock" \
  BARISTA_FLOCK_BIN="$BIN_DIR/missing_flock" \
  BARISTA_FILE_LOCK_SOURCE="$TMP_DIR/missing_file_lock.c" \
  BARISTA_FILE_LOCK_CC="$BIN_DIR/missing_cc"
[ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: missing lock backends should fail closed without applying visuals" >&2; exit 1; }
[ -z "$(find "$CONFIG_DIR/cache/space_visuals" -name '*.mkdir.lock' -print -quit 2>/dev/null)" ] || { echo "FAIL: visual locking must not leave a stale mkdir fallback" >&2; exit 1; }

# Lua-only/restricted-work mode must retain safe coalescing without compiling or
# executing a project-native helper.
cat > "$BIN_DIR/forbidden_file_lock" <<'EOF'
#!/bin/bash
printf 'called\n' >> "${BARISTA_TEST_FORBIDDEN_HELPER_LOG:?}"
exit 1
EOF
chmod +x "$BIN_DIR/forbidden_file_lock"
cat > "$BIN_DIR/forbidden_cc" <<'EOF'
#!/bin/bash
printf 'called\n' >> "${BARISTA_TEST_FORBIDDEN_CC_LOG:?}"
exit 1
EOF
chmod +x "$BIN_DIR/forbidden_cc"
forbidden_helper_log="$TMP_DIR/forbidden_file_lock.log"
forbidden_cc_log="$TMP_DIR/forbidden_cc.log"
PYTHON_BIN="$(command -v python3 2>/dev/null || true)"
[ -x "$PYTHON_BIN" ] || { echo "FAIL: python3 is required for the Lua-only lock boundary" >&2; exit 1; }

run_visual "manual" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PYTHON_BIN="$PYTHON_BIN" \
  BARISTA_FILE_LOCK_BIN="$TMP_DIR/lua_only_missing_file_lock" \
  BARISTA_FILE_LOCK_SOURCE="$ROOT_DIR/helpers/file_lock.c" \
  BARISTA_FILE_LOCK_CC="$BIN_DIR/forbidden_cc" \
  BARISTA_TEST_FORBIDDEN_CC_LOG="$forbidden_cc_log"
expected_visual_events=$((expected_visual_events + 1))
[ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: Lua-only mode should apply visuals through its safe portable lock" >&2; exit 1; }
[ ! -e "$forbidden_cc_log" ] || { echo "FAIL: Lua-only mode must not compile the native lock helper" >&2; exit 1; }

run_visual "manual" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PYTHON_BIN="$PYTHON_BIN" \
  BARISTA_FILE_LOCK_BIN="$BIN_DIR/forbidden_file_lock" \
  BARISTA_TEST_FORBIDDEN_HELPER_LOG="$forbidden_helper_log"
expected_visual_events=$((expected_visual_events + 1))
[ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: Lua-only mode should ignore an existing native lock helper" >&2; exit 1; }
[ ! -e "$forbidden_helper_log" ] || { echo "FAIL: Lua-only mode must not execute the native lock helper" >&2; exit 1; }

# The Python child locks the shell's inherited descriptor, so the lock remains
# owned by the parent after Python exits and a concurrent ordinary pass drops.
lua_only_owner_enter_file="$TMP_DIR/lua_only_owner_context_entered"
run_visual "front_app_switched" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PYTHON_BIN="$PYTHON_BIN" \
  BARISTA_FILE_LOCK_BIN="$TMP_DIR/lua_only_missing_file_lock" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  BARISTA_TEST_CONTEXT_ENTER_FILE="$lua_only_owner_enter_file" \
  BARISTA_TEST_CONTEXT_DELAY=0.30 \
  INFO="LuaOnlyOwner" &
lua_only_owner_pid=$!
lua_only_wait_attempts=100
while [ ! -e "$lua_only_owner_enter_file" ] && [ "$lua_only_wait_attempts" -gt 0 ]; do
  sleep 0.01
  lua_only_wait_attempts=$((lua_only_wait_attempts - 1))
done
[ -e "$lua_only_owner_enter_file" ] || { echo "FAIL: Lua-only visual owner did not acquire its portable lock" >&2; exit 1; }
run_visual "manual" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_PYTHON_BIN="$PYTHON_BIN" \
  BARISTA_FILE_LOCK_BIN="$TMP_DIR/lua_only_missing_file_lock"
wait "$lua_only_owner_pid"
expected_visual_events=$((expected_visual_events + 1))
[ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: Lua-only inherited-descriptor lock should suppress a concurrent ordinary pass" >&2; exit 1; }

# BARISTA_NO_CMAKE is the direct CLI alias for the same no-helper boundary.
no_cmake_cc_log="$TMP_DIR/no_cmake_forbidden_cc.log"
run_visual "manual" \
  BARISTA_NO_CMAKE=1 \
  BARISTA_PYTHON_BIN="$PYTHON_BIN" \
  BARISTA_FILE_LOCK_BIN="$TMP_DIR/no_cmake_missing_file_lock" \
  BARISTA_FILE_LOCK_SOURCE="$ROOT_DIR/helpers/file_lock.c" \
  BARISTA_FILE_LOCK_CC="$BIN_DIR/forbidden_cc" \
  BARISTA_TEST_FORBIDDEN_CC_LOG="$no_cmake_cc_log"
expected_visual_events=$((expected_visual_events + 1))
[ "$(count_visual_events)" = "$expected_visual_events" ] || { echo "FAIL: no-CMake mode should use the portable lock path" >&2; exit 1; }
[ ! -e "$no_cmake_cc_log" ] || { echo "FAIL: no-CMake mode must not compile the native lock helper" >&2; exit 1; }

printf 'test_space_visuals.sh: ok\n'
