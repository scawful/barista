#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/runtime_context.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
HELPER_BIN="$BIN_DIR/runtime_context_helper"
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
STATE_DIR="${BARISTA_RUNTIME_CONTEXT_DIR:?missing state dir}"
FRONT_APP_FILE="$STATE_DIR/front_app.tsv"

write_bad_cache() {
  mkdir -p "$STATE_DIR"
  {
    printf 'app_name\tGhostty\n'
    printf 'state_icon\t󰋽\n'
    printf 'state_label\tNo managed window\n'
    printf 'location_label\tSpace ? · Display ?\n'
    printf 'space_index\t\n'
    printf 'display_index\t\n'
    printf 'space_visible\tfalse\n'
  } > "$FRONT_APP_FILE"
}

case "${1:-}" in
  refresh-front-app)
    write_bad_cache
    ;;
  front-app|focused-space)
    write_bad_cache
    cat "$FRONT_APP_FILE"
    ;;
  daemon)
    trap 'exit 0' INT TERM
    while true; do
      write_bad_cache
      sleep 0.1
    done
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$HELPER_BIN"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  '-m query --spaces')
    cat <<'JSON'
[{"index":4,"display":1,"type":"bsp","is-visible":false,"has-focus":false},{"index":5,"display":1,"type":"bsp","is-visible":true,"has-focus":true}]
JSON
    ;;
  '-m query --spaces --space 5')
    cat <<'JSON'
{"index":5,"display":1,"type":"bsp","is-visible":true,"has-focus":true}
JSON
    ;;
  '-m query --windows --window')
    cat <<'JSON'
{"id":52,"app":"Ghostty","space":5,"display":1,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"above","is-minimized":false}
JSON
    ;;
  '-m query --windows')
    cat <<'JSON'
[{"id":41,"app":"Ghostty","space":4,"display":1,"has-focus":false,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"auto","is-minimized":false},{"id":52,"app":"Ghostty","space":5,"display":1,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"above","is-minimized":false}]
JSON
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'name of first process whose frontmost is true'*)
    printf 'Ghostty\n'
    ;;
  *'application "Spotify" is running'*)
    printf 'false\n'
    ;;
  *'application "Music" is running'*)
    printf 'false\n'
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
    printf 'Studio Display\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/SwitchAudioSource"

FRONT_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" front-app
)"
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'state_label\tTiled · Above' || { echo "FAIL: runtime context should fall back when helper front-app output does not match the focused window" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'location_label\tSpace 5 · Display 1' || { echo "FAIL: runtime context fallback should preserve the focused window location" >&2; exit 1; }

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_RUNTIME_CONTEXT_INTERVAL=5 \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" daemon >/dev/null 2>&1 &
DAEMON_PID=$!

sleep 0.3

if pgrep -P "$DAEMON_PID" -f 'runtime_context_helper daemon' >/dev/null 2>&1; then
  echo "FAIL: runtime context daemon should not launch the helper daemon when helper output is invalid" >&2
  exit 1
fi

grep -Fxq $'state_label\tTiled · Above' "$CONFIG_DIR/cache/runtime_context/front_app.tsv" || {
  echo "FAIL: runtime context daemon should keep the fallback front-app cache correct when helper output is invalid" >&2
  exit 1
}

printf 'test_runtime_context_helper_fallback.sh: ok\n'
