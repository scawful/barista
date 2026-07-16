#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/runtime_context.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
HELPER_BIN="$BIN_DIR/runtime_context_helper"
HELPER_LOG="$TMP_DIR/helper.log"
DAEMON_PID=""

cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    kill "$DAEMON_PID" >/dev/null 2>&1 || true
    wait "$DAEMON_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/cache" "$BIN_DIR"

cat > "$HELPER_BIN" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${BARISTA_TEST_HELPER_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$BARISTA_TEST_HELPER_LOG"
fi
STATE_DIR="${BARISTA_RUNTIME_CONTEXT_DIR:?missing state dir}"
FRONT_APP_FILE="$STATE_DIR/front_app.tsv"

write_cache() {
  mkdir -p "$STATE_DIR"
  cat > "$FRONT_APP_FILE" <<'TSV'
app_name	Finder
state_icon	󰆾
state_label	Tiled · Sticky
location_label	Space 2 · Display 1
space_index	2
display_index	1
space_visible	true
TSV
}

case "${1:-}" in
  refresh-front-app)
    write_cache
    ;;
  fresh-front-app)
    write_cache
    cat "$FRONT_APP_FILE"
    ;;
  front-app)
    [ -s "$FRONT_APP_FILE" ] || write_cache
    cat "$FRONT_APP_FILE"
    ;;
  focused-space)
    cat <<'TSV'
app_name	Cursor
state_icon	󰆾
state_label	Tiled
location_label	Space 4 · Display 1
space_index	4
display_index	1
space_visible	true
TSV
    ;;
  daemon)
    trap 'exit 0' INT TERM
    while true; do
      write_cache
      sleep "${BARISTA_RUNTIME_CONTEXT_INTERVAL:-1}"
    done
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$HELPER_BIN"
: > "$HELPER_LOG"

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'application "Spotify" is running'*)
    printf 'true\n'
    ;;
  *'application "Music" is running'*)
    printf 'false\n'
    ;;
  *'tell application "Spotify" to return (player state as string)'*)
    printf 'playing\n'
    ;;
  *'tell application "Spotify" to return (name of current track as string)'*)
    printf 'Clock Town\n'
    ;;
  *'tell application "Spotify" to return (artist of current track as string)'*)
    printf 'Koji Kondo\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  -c)
    printf 'Studio Display\n'
    ;;
  -a)
    printf 'Studio Display\nMacBook Pro Speakers\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/SwitchAudioSource"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  '-m query --spaces')
    cat <<'JSON'
[{"index":2,"display":1,"type":"bsp","is-visible":true,"has-focus":true}]
JSON
    ;;
  '-m query --windows --window')
    cat <<'JSON'
{"id":17,"app":"Finder","space":2,"display":1,"has-focus":true,"is-floating":false,"is-sticky":true,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"auto","is-minimized":false}
JSON
    ;;
  '-m query --windows')
    cat <<'JSON'
[{"id":17,"app":"Finder","space":2,"display":1,"has-focus":true,"is-floating":false,"is-sticky":true,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"auto","is-minimized":false}]
JSON
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/yabai"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" refresh

grep -Fxq $'app_name\tFinder' "$CONFIG_DIR/cache/runtime_context/front_app.tsv" || { echo "FAIL: runtime context should delegate front-app cache refresh to helper" >&2; exit 1; }
grep -Fxq $'window_available\ttrue' "$CONFIG_DIR/cache/runtime_context/front_app.tsv" || { echo "FAIL: runtime context should normalize helper-backed window availability" >&2; exit 1; }
grep -Fxq $'track\tClock Town' "$CONFIG_DIR/cache/runtime_context/media.tsv" || { echo "FAIL: runtime context should still refresh media cache alongside helper-backed front-app state" >&2; exit 1; }

FRONT_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" front-app
)"
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'location_label\tSpace 2 · Display 1' || { echo "FAIL: runtime context should print helper-backed front-app state" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'window_available\ttrue' || { echo "FAIL: runtime context should print normalized window availability" >&2; exit 1; }

FOCUSED_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" focused-space
)"
printf '%s\n' "$FOCUSED_OUTPUT" | grep -Fxq $'app_name\tCursor' || { echo "FAIL: focused-space should request a fresh helper-backed focused-space record" >&2; exit 1; }
printf '%s\n' "$FOCUSED_OUTPUT" | grep -Fxq $'location_label\tSpace 4 · Display 1' || { echo "FAIL: focused-space should not reuse stale cached front-app state" >&2; exit 1; }

: > "$HELPER_LOG"
FRESH_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_TEST_HELPER_LOG="$HELPER_LOG" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" fresh-front-app
)"
[ "$(cat "$HELPER_LOG")" = "fresh-front-app" ] || {
  echo "FAIL: compiled popup refresh should invoke exactly one native fresh-front-app command" >&2
  cat "$HELPER_LOG" >&2
  exit 1
}
printf '%s\n' "$FRESH_OUTPUT" | grep -Fxq $'app_name\tFinder' || {
  echo "FAIL: compiled popup refresh should forward the native fresh snapshot" >&2
  exit 1
}

: > "$HELPER_LOG"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_LUA_ONLY=1 \
  BARISTA_TEST_HELPER_LOG="$HELPER_LOG" \
  BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" fresh-front-app >/dev/null
[ ! -s "$HELPER_LOG" ] || {
  echo "FAIL: explicit Lua-only popup refresh should not reactivate the compiled helper" >&2
  exit 1
}

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_RUNTIME_CONTEXT_INTERVAL=0.1 \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" daemon >/dev/null 2>&1 &
DAEMON_PID=$!

for _ in {1..50}; do
  if [ -s "$CONFIG_DIR/cache/runtime_context/front_app.tsv" ] &&
     [ -s "$CONFIG_DIR/cache/runtime_context/media.tsv" ]; then
    break
  fi
  sleep 0.05
done

[ -s "$CONFIG_DIR/cache/runtime_context/front_app.tsv" ] || { echo "FAIL: runtime context daemon should keep helper-backed front-app cache warm" >&2; exit 1; }
[ -s "$CONFIG_DIR/cache/runtime_context/media.tsv" ] || { echo "FAIL: runtime context daemon should keep media cache warm while helper daemon runs" >&2; exit 1; }

kill "$DAEMON_PID" >/dev/null 2>&1 || true
wait "$DAEMON_PID" >/dev/null 2>&1 || true
DAEMON_PID=""

printf 'test_runtime_context_helper.sh: ok\n'
