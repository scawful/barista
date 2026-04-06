#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/media_control.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/media_actions.log"
OUTPUT_LOG_FILE="$TMP_DIR/output_actions.log"
RUNTIME_CONTEXT_STUB="$TMP_DIR/runtime_context_stub.sh"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
cat > "$RUNTIME_CONTEXT_STUB" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$RUNTIME_CONTEXT_STUB"

cat > "$BIN_DIR/osascript" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
case "\$*" in
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
    printf 'Ballad of the Wind Fish\n'
    ;;
  *'tell application "Spotify" to return (artist of current track as string)'*)
    printf 'Koholint Ensemble\n'
    ;;
  *'tell application "Spotify" to playpause'*)
    printf 'playpause\n' >> "\$LOG_FILE"
    ;;
  *'tell application "Spotify" to next track'*)
    printf 'next\n' >> "\$LOG_FILE"
    ;;
  *'tell application "Spotify" to previous track'*)
    printf 'previous\n' >> "\$LOG_FILE"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<EOF
#!/bin/bash
set -euo pipefail
OUTPUT_LOG_FILE="$OUTPUT_LOG_FILE"
case "\${1:-}" in
  -c)
    printf 'Studio Display\\n'
    ;;
  -a)
    printf 'Studio Display\\nMacBook Pro Speakers\\n'
    ;;
  -s)
    printf '%s\\n' "\${2:-}" >> "\$OUTPUT_LOG_FILE"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/SwitchAudioSource"

STATUS_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" \
    "$SCRIPT" status
)"

printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'player\tSpotify' || { echo "FAIL: status should resolve Spotify as the active player" >&2; exit 1; }
printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'state\tplaying' || { echo "FAIL: status should report player state" >&2; exit 1; }
printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'track\tBallad of the Wind Fish' || { echo "FAIL: status should expose current track" >&2; exit 1; }
printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'artist\tKoholint Ensemble' || { echo "FAIL: status should expose current artist" >&2; exit 1; }
printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'toggle_label\tPause' || { echo "FAIL: status should expose pause label while playing" >&2; exit 1; }
printf '%s\n' "$STATUS_OUTPUT" | grep -Fxq $'current_output\tStudio Display' || { echo "FAIL: status should expose current output" >&2; exit 1; }

OUTPUTS_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" \
    "$SCRIPT" outputs
)"

printf '%s\n' "$OUTPUTS_OUTPUT" | grep -Fxq $'output\t1\ttrue\tStudio Display' || { echo "FAIL: outputs should mark the active route" >&2; exit 1; }
printf '%s\n' "$OUTPUTS_OUTPUT" | grep -Fxq $'output\t2\tfalse\tMacBook Pro Speakers' || { echo "FAIL: outputs should include alternate routes" >&2; exit 1; }

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" "$SCRIPT" playpause
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" "$SCRIPT" next
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" "$SCRIPT" previous
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" BARISTA_RUNTIME_CONTEXT_SCRIPT="$RUNTIME_CONTEXT_STUB" "$SCRIPT" set-output 2

grep -Fxq 'playpause' "$LOG_FILE" || { echo "FAIL: playpause command should be dispatched" >&2; exit 1; }
grep -Fxq 'next' "$LOG_FILE" || { echo "FAIL: next command should be dispatched" >&2; exit 1; }
grep -Fxq 'previous' "$LOG_FILE" || { echo "FAIL: previous command should be dispatched" >&2; exit 1; }
grep -Fxq 'MacBook Pro Speakers' "$OUTPUT_LOG_FILE" || { echo "FAIL: set-output should dispatch the selected output route" >&2; exit 1; }

printf 'test_media_control.sh: ok\n'
