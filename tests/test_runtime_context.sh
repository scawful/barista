#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/runtime_context.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
OUTPUT_LOG="$TMP_DIR/output.log"
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

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
case "${RUNTIME_CONTEXT_TEST_MODE:-default}:$*" in
  'default:-m query --spaces')
    printf '[{"index":3,"display":1,"is-visible":true,"has-focus":true}]\n'
    ;;
  'default:-m query --windows --window')
    printf ''
    ;;
  'default:-m query --windows')
    printf '[{"id":12,"app":"Ghostty","space":3,"display":1,"is-floating":false,"is-sticky":true,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}]\n'
    ;;
  'backfill:-m query --spaces')
    printf '[]\n'
    ;;
  'backfill:-m query --windows --window')
    printf '{"id":41,"app":"Ghostty","space":7,"display":2,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}\n'
    ;;
  'backfill:-m query --windows')
    printf '[{"id":41,"app":"Ghostty","space":7,"display":2,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}]\n'
    ;;
  *)
    exit 1
    ;;
esac
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/osascript" <<'OSA'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'name of first process whose frontmost is true'*)
    printf 'Ghostty\n'
    ;;
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
    printf 'Gerudo Valley\n'
    ;;
  *'tell application "Spotify" to return (artist of current track as string)'*)
    printf 'Koji Kondo\n'
    ;;
  *)
    exit 1
    ;;
esac
OSA
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<EOF2
#!/bin/bash
set -euo pipefail
OUTPUT_LOG="$OUTPUT_LOG"
if [ "\${1:-}" = "-c" ]; then
  printf 'Studio Display\n'
  exit 0
fi
if [ "\${1:-}" = "-a" ]; then
  printf 'Studio Display\nMacBook Pro Speakers\n'
  exit 0
fi
if [ "\${1:-}" = "-s" ]; then
  printf '%s\n' "\${2:-}" >> "$OUTPUT_LOG"
  exit 0
fi
exit 1
EOF2
chmod +x "$BIN_DIR/SwitchAudioSource"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" refresh

grep -Fxq $'current_output\tStudio Display' "$CONFIG_DIR/cache/runtime_context/media.tsv" || { echo "FAIL: runtime context should persist current output in the media cache" >&2; exit 1; }

FRONT_OUTPUT="$({
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" front-app
})"
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'app_name\tGhostty' || { echo "FAIL: runtime context should cache front app name" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'state_label\tTiled · Sticky' || { echo "FAIL: runtime context should cache front app state" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'location_label\tSpace 3 · Display 1' || { echo "FAIL: runtime context should cache front app location" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'space_index\t3' || { echo "FAIL: runtime context should cache raw front app space index" >&2; exit 1; }
printf '%s\n' "$FRONT_OUTPUT" | grep -Fxq $'display_index\t1' || { echo "FAIL: runtime context should cache raw front app display index" >&2; exit 1; }

BACKFILL_OUTPUT="$({
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    RUNTIME_CONTEXT_TEST_MODE=backfill \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" refresh front-app >/dev/null 2>&1
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    RUNTIME_CONTEXT_TEST_MODE=backfill \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" front-app
})"
printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'space_index\t7' || { echo "FAIL: runtime context should backfill raw space index from the selected window when current-space discovery is missing" >&2; exit 1; }
printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'display_index\t2' || { echo "FAIL: runtime context should backfill raw display index from the selected window when current-space discovery is missing" >&2; exit 1; }
printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'space_visible\ttrue' || { echo "FAIL: runtime context should mark the focused selected window as visible when backfilling" >&2; exit 1; }

MEDIA_OUTPUT="$({
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" media-status
})"
printf '%s\n' "$MEDIA_OUTPUT" | grep -Fxq $'player\tSpotify' || { echo "FAIL: runtime context should cache media player" >&2; exit 1; }
printf '%s\n' "$MEDIA_OUTPUT" | grep -Fxq $'track\tGerudo Valley' || { echo "FAIL: runtime context should cache media track" >&2; exit 1; }

OUTPUTS_OUTPUT="$({
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$(command -v jq)" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    CONFIG_DIR="$CONFIG_DIR" \
    "$SCRIPT" outputs
})"
printf '%s\n' "$OUTPUTS_OUTPUT" | grep -Fxq $'output\t1\ttrue\tStudio Display' || { echo "FAIL: runtime context should cache active output" >&2; exit 1; }
printf '%s\n' "$OUTPUTS_OUTPUT" | grep -Fxq $'output\t2\tfalse\tMacBook Pro Speakers' || { echo "FAIL: runtime context should cache alternate output" >&2; exit 1; }

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" switch-output 2

grep -Fxq 'MacBook Pro Speakers' "$OUTPUT_LOG" || { echo "FAIL: runtime context should switch outputs by cached index" >&2; exit 1; }

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
  BARISTA_JQ_BIN="$(command -v jq)" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_RUNTIME_CONTEXT_INTERVAL=0.1 \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" daemon >/dev/null 2>&1 &
DAEMON_PID=$!
sleep 0.2
[ -s "$CONFIG_DIR/cache/runtime_context/front_app.tsv" ] || { echo "FAIL: runtime context daemon should keep front app cache warm" >&2; exit 1; }
[ -s "$CONFIG_DIR/cache/runtime_context/media.tsv" ] || { echo "FAIL: runtime context daemon should keep media cache warm" >&2; exit 1; }
kill "$DAEMON_PID" >/dev/null 2>&1 || true
wait "$DAEMON_PID" >/dev/null 2>&1 || true
DAEMON_PID=""

printf 'test_runtime_context.sh: ok\n'
