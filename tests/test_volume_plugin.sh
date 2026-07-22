#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/volume.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
MEDIA_STUB="$TMP_DIR/media_control.sh"
MEDIA_LOG="$TMP_DIR/media_control.log"
NATIVE_STUB="$TMP_DIR/volume_popup_helper"
NATIVE_LOG="$TMP_DIR/volume_popup_helper.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${BARISTA_TEST_SKETCHYBAR_LOG:?}"
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'output volume of (get volume settings)'*) printf '50\n' ;;
  *'output muted of (get volume settings)'*) printf '%s\n' "${BARISTA_TEST_MUTED:-false}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  -c) printf 'Studio Display\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN_DIR/SwitchAudioSource"

cat > "$MEDIA_STUB" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${BARISTA_TEST_MEDIA_LOG:-}" ]; then
  printf '%s\n' "${1:-}" >> "$BARISTA_TEST_MEDIA_LOG"
fi
case "${1:-}" in
  status)
    printf 'player\tMusic\n'
    printf 'state\tplaying\n'
    printf 'track\tGirl, so confusing featuring lorde\n'
    printf 'artist\tCharli xcx\n'
    printf 'toggle_label\tPause\n'
    printf 'toggle_icon\t󰏤\n'
    printf 'current_output\tStudio Display\n'
    ;;
  outputs)
    printf 'output\t1\ttrue\tStudio Display\n'
    printf 'output\t2\tfalse\tMacBook Pro Speakers\n'
    ;;
esac
EOF
chmod +x "$MEDIA_STUB"
: > "$MEDIA_LOG"

cat > "$NATIVE_STUB" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${BARISTA_TEST_NATIVE_LOG:?}"
exit "${BARISTA_TEST_NATIVE_RC:-0}"
EOF
chmod +x "$NATIVE_STUB"

# Routine updates prefer the same native CoreAudio path as popup clicks.
: > "$NATIVE_LOG"
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_VOLUME_POPUP_HELPER="$NATIVE_STUB" \
  BARISTA_TEST_NATIVE_LOG="$NATIVE_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"
grep -Fxq -- 'popup_refresh' "$NATIVE_LOG" || {
  echo "FAIL: routine volume updates should prefer the native helper" >&2
  exit 1
}
if [ -s "$LOG_FILE" ]; then
  echo "FAIL: a successful native routine update should skip the shell refresh" >&2
  exit 1
fi

# A native routine failure keeps the portable shell behavior available.
: > "$NATIVE_LOG"
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=volume_change \
  INFO=50 \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_VOLUME_POPUP_HELPER="$NATIVE_STUB" \
  BARISTA_TEST_NATIVE_LOG="$NATIVE_LOG" \
  BARISTA_TEST_NATIVE_RC=3 \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"
grep -Fxq -- 'popup_refresh' "$NATIVE_LOG" || {
  echo "FAIL: volume-change updates should attempt the native helper" >&2
  exit 1
}
grep -Fq -- '--set volume.state icon=󰖀 label=Volume: 50%' "$LOG_FILE" || {
  echo "FAIL: a failed native routine update should retain the shell fallback" >&2
  exit 1
}

# An explicit popup fallback must skip native delegation and complete in shell.
: > "$NATIVE_LOG"
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_VOLUME_POPUP_HELPER="$NATIVE_STUB" \
  BARISTA_TEST_NATIVE_LOG="$NATIVE_LOG" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT" popup_refresh
if [ -s "$NATIVE_LOG" ]; then
  echo "FAIL: the shell popup fallback must not retry the failed native helper" >&2
  exit 1
fi
grep -Fq -- '--set volume.state' "$LOG_FILE" || {
  echo "FAIL: the explicit popup fallback should run the shell refresh" >&2
  exit 1
}

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"

grep -Fq -- '--set volume.state icon=󰖀 label=Volume: 50%' "$LOG_FILE" || {
  echo "FAIL: volume state row should use the approved Volume prefix" >&2
  exit 1
}
grep -Fq -- '--set volume.output label=Output: Studio Display' "$LOG_FILE" || {
  echo "FAIL: output row should use the approved Output prefix" >&2
  exit 1
}
grep -Fq -- '--set volume.media icon=' "$LOG_FILE" || {
  echo "FAIL: now-playing row should be updated" >&2
  exit 1
}
grep -Fq -- 'label=Now Playing: Girl, so confusing featuring lorde — Charli xcx' "$LOG_FILE" || {
  echo "FAIL: media row should use the approved Now Playing prefix" >&2
  exit 1
}
grep -Fq -- '--set volume.output.1 drawing=on icon=󰓃 label=Studio Display · Current' "$LOG_FILE" || {
  echo "FAIL: selected output row should be visible and marked current" >&2
  exit 1
}
grep -Fq -- '--set volume.output.2 drawing=on icon=󰓃 label=MacBook Pro Speakers' "$LOG_FILE" || {
  echo "FAIL: alternate output row should be visible" >&2
  exit 1
}
grep -Fq -- '--set volume.mute drawing=on icon=󰕾 label=Mute' "$LOG_FILE" || {
  echo "FAIL: the shell fallback should redraw an available mute action" >&2
  exit 1
}
grep -Fxq -- 'outputs' "$MEDIA_LOG" || {
  echo "FAIL: available output switching should load output routes" >&2
  exit 1
}

: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_MEDIA_LABEL_MAX=32 \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"

grep -Fq -- 'label=Now Playing: Girl, so confusing…' "$LOG_FILE" || {
  echo "FAIL: media row should truncate overly long labels without extra process work" >&2
  exit 1
}

: > "$LOG_FILE"
: > "$MEDIA_LOG"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$TMP_DIR/missing-switch-audio-source" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"

grep -Fxq -- 'status' "$MEDIA_LOG" || {
  echo "FAIL: unavailable output switching should still load cached media status" >&2
  exit 1
}
if grep -Fxq -- 'outputs' "$MEDIA_LOG"; then
  echo "FAIL: unavailable output switching should not rediscover unusable output routes" >&2
  exit 1
fi
for index in 1 2 3 4; do
  grep -Fq -- "--set volume.output.$index drawing=off label=" "$LOG_FILE" || {
    echo "FAIL: unavailable output switching should keep route $index hidden" >&2
    exit 1
  }
done

# A muted software-controllable fallback also restores the previously hidden row.
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  SENDER=routine \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_TEST_MUTED=true \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$TMP_DIR/missing-switch-audio-source" \
  BARISTA_MEDIA_CONTROL_SCRIPT="$MEDIA_STUB" \
  BARISTA_TEST_MEDIA_LOG="$MEDIA_LOG" \
  BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
  "$SCRIPT"
grep -Fq -- '--set volume.mute drawing=on icon=󰖁 label=Unmute' "$LOG_FILE" || {
  echo "FAIL: the muted shell fallback should redraw the mute action" >&2
  exit 1
}

printf 'test_volume_plugin.sh: ok\n'
