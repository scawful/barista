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
printf 'X'
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
    BARISTA_SPACE_VISUAL_HELPER_BIN="$BIN_DIR/space_visual_helper"
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
mkdir "$CONFIG_DIR/.space_visuals.lock"
run_visual "manual"
[ "$(count_visual_events)" = "4" ] || { echo "FAIL: locked refresh should not add a visual event" >&2; exit 1; }
rmdir "$CONFIG_DIR/.space_visuals.lock"

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

printf 'test_space_visuals.sh: ok\n'
