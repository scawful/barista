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
TIMEOUT_BIN="$(command -v timeout || true)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$SCRIPTS_DIR" "$CONFIG_DIR/cache" "$CONFIG_DIR/bin" "$BAR_STATE_DIR"
cp "$STATS_SCRIPT" "$CONFIG_DIR/bin/barista-stats.sh"
chmod +x "$CONFIG_DIR/bin/barista-stats.sh"

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
  printf '[{"display":1,"index":1,"is-visible":true,"type":"bsp"},{"display":1,"index":2,"is-visible":false,"type":"bsp"}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--windows" ]; then
  if [ "${4:-}" = "--space" ]; then
    if [ "${5:-}" = "1" ]; then
      printf '[{"space":1,"app":"FocusApp","has-focus":true,"is-minimized":false,"id":10}]\n'
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
  printf '{"items":["space.1","space.2"]}\n'
  exit 0
fi
if [ "${1:-}" = "--query" ] && [[ "${2:-}" == space.* ]]; then
  item="${2#space.}"
  icon=""
  [ -f "$STATE_DIR/$item.icon" ] && icon="$(cat "$STATE_DIR/$item.icon")"
  printf '{"icon":{"value":"%s"}}\n' "$icon"
  exit 0
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
printf 'X'
EOF
chmod +x "$SCRIPTS_DIR/app_icon.sh"

cat > "$SCRIPTS_DIR/front_app_context.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'app_name\tFocusApp\n'
printf 'space_index\t1\n'
printf 'display_index\t1\n'
printf 'space_visible\ttrue\n'
EOF
chmod +x "$SCRIPTS_DIR/front_app_context.sh"

run_visual() {
  local sender="$1"
  shift
  local -a cmd=(
    env
    PATH="$BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar"
    BARISTA_YABAI_BIN="$BIN_DIR/yabai"
    CONFIG_DIR="$CONFIG_DIR"
    SCRIPTS_DIR="$SCRIPTS_DIR"
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh"
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

run_visual "manual"
[ "$(count_visual_events)" = "1" ] || { echo "FAIL: manual refresh should log exactly one event" >&2; exit 1; }
[ "$("$BIN_DIR/sketchybar" --query space.2 | jq -r '.icon.value')" != "bsp" ] || { echo "FAIL: space_modes must not leak into space icons" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "1" ] || { echo "FAIL: first authoritative refresh should query the bar exactly once to build the space-item cache" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: authoritative refresh should not query the full windows snapshot" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows --space 1")" = "1" ] || { echo "FAIL: authoritative refresh should resolve the visible space app from a scoped window query" >&2; exit 1; }

: > "$YABAI_LOG"
run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0 \
  INFO="FocusApp"
[ "$(count_visual_events)" = "2" ] || { echo "FAIL: focused front_app refresh should be recorded" >&2; exit 1; }
[ "$(count_yabai_line "-m query --spaces --space")" = "0" ] || { echo "FAIL: focused front_app refresh should not query the focused space directly when the helper provides it" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: focused front_app refresh should not query all windows" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "1" ] || { echo "FAIL: focused front_app refresh should reuse cached space-item lookup instead of querying the full bar again" >&2; exit 1; }

: > "$YABAI_LOG"
run_visual "space_active_refresh" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "3" ] || { echo "FAIL: focused active-space refresh should be recorded" >&2; exit 1; }
[ "$(count_yabai_line "-m query --spaces")" = "0" ] || { echo "FAIL: focused active-space refresh should not query all spaces" >&2; exit 1; }
[ "$(count_yabai_line "-m query --windows")" = "0" ] || { echo "FAIL: focused active-space refresh should not query all windows" >&2; exit 1; }
[ "$(count_sketchybar_line $'query\tbar')" = "1" ] || { echo "FAIL: focused active-space refresh should reuse cached space-item lookup instead of querying the full bar again" >&2; exit 1; }

rm -f "$CONFIG_DIR/cache/space_visuals/last_front_app_refresh_ms" "$CONFIG_DIR/cache/space_visuals/last_authoritative_refresh_ms"
mkdir "$CONFIG_DIR/.space_visuals.lock"
run_visual "manual"
[ "$(count_visual_events)" = "3" ] || { echo "FAIL: locked refresh should not add a visual event" >&2; exit 1; }
rmdir "$CONFIG_DIR/.space_visuals.lock"

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: first front_app_switched should be recorded when cooldown is disabled" >&2; exit 1; }

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=0 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=5000
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: front_app debounce should suppress the second rapid refresh" >&2; exit 1; }

run_visual "space_topology_refresh" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "5" ] || { echo "FAIL: topology refresh should be recorded" >&2; exit 1; }

run_visual "front_app_switched" \
  BARISTA_SPACE_FRONT_APP_COOLDOWN_MS=5000 \
  BARISTA_SPACE_FRONT_APP_DEBOUNCE_MS=0
[ "$(count_visual_events)" = "5" ] || { echo "FAIL: cooldown should suppress front_app refresh after topology refresh" >&2; exit 1; }

printf 'test_space_visuals.sh: ok\n'
