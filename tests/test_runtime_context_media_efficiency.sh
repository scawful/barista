#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/runtime_context.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
STATE_DIR="$TMP_DIR/state"
OSASCRIPT_LOG="$TMP_DIR/osascript.log"
AUDIO_LOG="$TMP_DIR/audio.log"
TRACK_FILE="$TMP_DIR/track"
CURRENT_OUTPUT_FILE="$TMP_DIR/current-output"
OUTPUT_LIST_FILE="$TMP_DIR/output-list"
HELPER_PID_LOG="$TMP_DIR/helper-pids"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

stop_helpers() {
  [ -f "$HELPER_PID_LOG" ] || return 0
  while IFS= read -r pid; do
    case "$pid" in
      ''|*[!0-9]*) continue ;;
    esac
    kill "$pid" >/dev/null 2>&1 || true
  done < "$HELPER_PID_LOG"
  : > "$HELPER_PID_LOG"
}

cleanup() {
  stop_helpers
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$STATE_DIR"
: > "$OSASCRIPT_LOG"
: > "$AUDIO_LOG"
: > "$HELPER_PID_LOG"
printf 'First Track\n' > "$TRACK_FILE"
printf 'Studio Display\n' > "$CURRENT_OUTPUT_FILE"
cat > "$OUTPUT_LIST_FILE" <<'EOF_OUTPUTS'
Studio Display
MacBook Pro Speakers
HDMI Display
USB DAC
Fifth Route
Sixth Route
EOF_OUTPUTS

cat > "$BIN_DIR/osascript" <<'EOF_OSASCRIPT'
#!/bin/bash
set -euo pipefail

script="$*"
printf 'call\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"

if [[ "$script" == *barista-media-v1* ]]; then
  printf 'media\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
  case "${BARISTA_TEST_MEDIA_SCENARIO:-playing}" in
    malformed)
      printf 'snapshot_version\tbroken\nplayer\tSpotify\n'
      ;;
    paused)
      printf 'snapshot_version\tbarista-media-v1\n'
      printf 'player\tSpotify\nstate\tpaused\ntrack\tPaused Track\nartist\tTest Artist\n'
      ;;
    none)
      printf 'snapshot_version\tbarista-media-v1\n'
      printf 'player\t\nstate\tstopped\ntrack\t\nartist\t\n'
      ;;
    playing|*)
      printf 'snapshot_version\tbarista-media-v1\n'
      printf 'player\tSpotify\nstate\tplaying\ntrack\t%s\nartist\tTest Artist\n' \
        "$(cat "${BARISTA_TEST_TRACK_FILE:?}")"
      ;;
  esac
  exit 0
fi

# Legacy per-field responses exercise the fail-safe parser path.
case "$script" in
  *'name of first process whose frontmost is true'*)
    sleep "${BARISTA_TEST_FRONT_DELAY:-0}"
    printf 'Finder\n'
    ;;
  *'application "Spotify" is running'*)
    printf 'legacy\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
    printf 'true\n'
    ;;
  *'application "Music" is running'*)
    printf 'legacy\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
    printf 'false\n'
    ;;
  *'tell application "Spotify" to return (player state as string)'*)
    printf 'legacy\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
    printf 'playing\n'
    ;;
  *'tell application "Spotify" to return (name of current track as string)'*)
    printf 'legacy\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
    printf 'Legacy Track\n'
    ;;
  *'tell application "Spotify" to return (artist of current track as string)'*)
    printf 'legacy\n' >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
    printf 'Legacy Artist\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF_OSASCRIPT
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<'EOF_AUDIO'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  -c)
    printf 'current\n' >> "${BARISTA_TEST_AUDIO_LOG:?}"
    current="$(cat "${BARISTA_TEST_CURRENT_OUTPUT_FILE:?}" 2>/dev/null || true)"
    [ "$current" != "__FAIL__" ] || exit 1
    printf '%s\n' "$current"
    ;;
  -a)
    printf 'list\n' >> "${BARISTA_TEST_AUDIO_LOG:?}"
    cat "${BARISTA_TEST_OUTPUT_LIST_FILE:?}"
    ;;
  -s)
    printf 'set\t%s\n' "${2:-}" >> "${BARISTA_TEST_AUDIO_LOG:?}"
    printf '%s\n' "${2:-}" > "${BARISTA_TEST_CURRENT_OUTPUT_FILE:?}"
    ;;
  *)
    exit 1
    ;;
esac
EOF_AUDIO
chmod +x "$BIN_DIR/SwitchAudioSource"

# The daemon only needs a warm front-app producer. Keeping it stubbed isolates
# media cadence counts from unrelated frontmost-app AppleScript calls.
cat > "$BIN_DIR/runtime_context_helper" <<'EOF_HELPER'
#!/bin/bash
set -euo pipefail

write_cache() {
  mkdir -p "${BARISTA_RUNTIME_CONTEXT_DIR:?}"
  printf '%s\n' \
    $'app_name\t' \
    $'window_available\tfalse' \
    $'state_icon\t' \
    $'state_label\tNo managed window' \
    $'location_label\tSpace ? · Display ?' \
    $'space_index\t' \
    $'display_index\t' \
    $'space_visible\tfalse' \
    > "${BARISTA_RUNTIME_CONTEXT_DIR}/front_app.tsv"
}

case "${1:-}" in
  refresh-front-app)
    write_cache
    ;;
  daemon)
    printf '%s\n' "$$" >> "${BARISTA_TEST_HELPER_PID_LOG:?}"
    trap 'exit 0' INT TERM
    while true; do sleep 0.05; done
    ;;
  *)
    exit 1
    ;;
esac
EOF_HELPER
chmod +x "$BIN_DIR/runtime_context_helper"

base_env=(
  "PATH=$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  "CONFIG_DIR=$TMP_DIR/config"
  "BARISTA_RUNTIME_CONTEXT_DIR=$STATE_DIR"
  "BARISTA_RUNTIME_CONTEXT_HELPER_BIN=$TMP_DIR/missing-helper"
  "BARISTA_YABAI_BIN=/usr/bin/false"
  "BARISTA_JQ_BIN=/usr/bin/false"
  "BARISTA_OSASCRIPT_BIN=$BIN_DIR/osascript"
  "BARISTA_SWITCH_AUDIO_SOURCE_BIN=$BIN_DIR/SwitchAudioSource"
  "BARISTA_TEST_OSASCRIPT_LOG=$OSASCRIPT_LOG"
  "BARISTA_TEST_AUDIO_LOG=$AUDIO_LOG"
  "BARISTA_TEST_TRACK_FILE=$TRACK_FILE"
  "BARISTA_TEST_CURRENT_OUTPUT_FILE=$CURRENT_OUTPUT_FILE"
  "BARISTA_TEST_OUTPUT_LIST_FILE=$OUTPUT_LIST_FILE"
  "BARISTA_TEST_HELPER_PID_LOG=$HELPER_PID_LOG"
)

run_context() {
  env "${base_env[@]}" \
    "BARISTA_TEST_MEDIA_SCENARIO=${MEDIA_SCENARIO:-playing}" \
    "$SCRIPT" "$@"
}

# Media timeouts must not bleed into the portable front-app/TCC probe.
slow_front_output="$(
  env "${base_env[@]}" \
    BARISTA_TEST_FRONT_DELAY=0.05 \
    BARISTA_RUNTIME_CONTEXT_OSASCRIPT_TIMEOUT=0.01 \
    "$SCRIPT" front-app
)"
printf '%s\n' "$slow_front_output" | grep -Fxq $'app_name\tFinder' \
  || fail "media timeout should not truncate the portable front-app probe"

file_identity() {
  python3 - "$1" <<'PY'
import os
import sys

status = os.stat(sys.argv[1], follow_symlinks=False)
print(f"{status.st_ino}:{status.st_mtime_ns}")
PY
}

MEDIA_SCENARIO=playing
: > "$OSASCRIPT_LOG"
run_context refresh media
[ "$(grep -c '^call$' "$OSASCRIPT_LOG" || true)" = "1" ] \
  || fail "a valid barista-media-v1 snapshot should use one osascript invocation"
grep -Fxq $'track\tFirst Track' "$STATE_DIR/media.tsv" \
  || fail "valid combined snapshot should populate the media cache"
if grep -q '^snapshot_version' "$STATE_DIR/media.tsv"; then
  fail "transport snapshot marker must not leak into the stable media cache"
fi

# Identical snapshots must not replace either cache file.
media_identity="$(file_identity "$STATE_DIR/media.tsv")"
outputs_identity="$(file_identity "$STATE_DIR/outputs.tsv")"
: > "$OSASCRIPT_LOG"
run_context refresh media
[ "$(file_identity "$STATE_DIR/media.tsv")" = "$media_identity" ] \
  || fail "unchanged media cache should preserve inode and mtime"
[ "$(file_identity "$STATE_DIR/outputs.tsv")" = "$outputs_identity" ] \
  || fail "unchanged outputs cache should preserve inode and mtime"

# Changed content must atomically replace the old snapshot.
printf 'Second Track\n' > "$TRACK_FILE"
run_context refresh media
grep -Fxq $'track\tSecond Track' "$STATE_DIR/media.tsv" \
  || fail "changed track should replace the cached media snapshot"
if grep -Fq 'First Track' "$STATE_DIR/media.tsv"; then
  fail "changed track refresh should not retain stale media content"
fi

# Character caps must not split a composed UTF-8 value at the byte boundary.
python3 - "$TRACK_FILE" <<'PY_UTF8_TRACK'
import sys

with open(sys.argv[1], "w", encoding="utf-8") as stream:
    stream.write("a" * 511 + "😀\n")
PY_UTF8_TRACK
run_context refresh media
python3 - "$STATE_DIR/media.tsv" <<'PY_UTF8_CACHE' \
  || fail "media field truncation should preserve valid UTF-8"
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    rows = dict(line.rstrip("\n").split("\t", 1) for line in stream)
assert len(rows["track"]) == 512
assert rows["track"].endswith("😀")
PY_UTF8_CACHE

# Exact comparison must repair NUL-suffixed and oversized regular caches
# instead of mistaking the expected prefix for a complete valid snapshot.
python3 - "$STATE_DIR/media.tsv" <<'PY_CORRUPT_CACHE'
import sys

with open(sys.argv[1], "ab") as stream:
    stream.write(b"\0JUNK")
PY_CORRUPT_CACHE
run_context refresh media
python3 - "$STATE_DIR/media.tsv" <<'PY_CHECK_NUL' \
  || fail "NUL-suffixed media cache should be atomically repaired"
import sys

data = open(sys.argv[1], "rb").read()
assert b"\0" not in data
assert b"JUNK" not in data
data.decode("utf-8")
PY_CHECK_NUL

python3 - "$STATE_DIR/media.tsv" <<'PY_OVERSIZED_CACHE'
import sys

with open(sys.argv[1], "ab") as stream:
    stream.write(b"x" * 70000)
PY_OVERSIZED_CACHE
run_context refresh media
[ "$(wc -c < "$STATE_DIR/media.tsv" | tr -d ' ')" -lt 65536 ] \
  || fail "oversized media cache should be replaced with the bounded snapshot"

# Even an equal-content symlink must be repaired to a regular cache file.
printf 'Second Track\n' > "$TRACK_FILE"
run_context refresh media
cp "$STATE_DIR/media.tsv" "$TMP_DIR/symlink-target.tsv"
rm -f "$STATE_DIR/media.tsv"
ln -s "$TMP_DIR/symlink-target.tsv" "$STATE_DIR/media.tsv"
run_context refresh media
[ ! -L "$STATE_DIR/media.tsv" ] && [ -f "$STATE_DIR/media.tsv" ] \
  || fail "media publisher should replace a symlink with a regular file"
grep -Fxq $'track\tSecond Track' "$STATE_DIR/media.tsv" \
  || fail "repaired media cache should retain the current snapshot"

# Malformed combined output must fail closed into the established per-field path.
MEDIA_SCENARIO=malformed
: > "$OSASCRIPT_LOG"
run_context refresh media
grep -Fxq $'track\tLegacy Track' "$STATE_DIR/media.tsv" \
  || fail "malformed combined snapshot should use legacy media probes"
[ "$(grep -c '^legacy$' "$OSASCRIPT_LOG" || true)" -gt 0 ] \
  || fail "malformed combined snapshot should invoke the legacy fallback"

# A failed current-output query must not guess that the first enumerated route
# is current, and the public popup cache stays capped at four routes.
MEDIA_SCENARIO=playing
printf '__FAIL__\n' > "$CURRENT_OUTPUT_FILE"
run_context refresh media
if grep -q $'^output\t[1-4]\ttrue\t' "$STATE_DIR/outputs.tsv"; then
  fail "failed current-output query should leave every route unselected"
fi
[ "$(awk -F'\t' '$1 == "output" { count++ } END { print count + 0 }' "$STATE_DIR/outputs.tsv")" = "4" ] \
  || fail "outputs cache should expose at most four routes"
if grep -q $'^output\t5\t' "$STATE_DIR/outputs.tsv"; then
  fail "outputs cache should not expose a fifth route"
fi

# The clicked index belongs to the cached/displayed name. Re-enumerating before
# resolving it could reorder devices and switch a different route.
printf 'Displayed One\n' > "$CURRENT_OUTPUT_FILE"
cat > "$OUTPUT_LIST_FILE" <<'EOF_DISPLAYED'
Displayed One
Displayed Two
EOF_DISPLAYED
run_context refresh media
displayed_name="$(awk -F'\t' '$1 == "output" && $2 == "2" { print $4; exit }' "$STATE_DIR/outputs.tsv")"
[ "$displayed_name" = "Displayed Two" ] || fail "fixture should cache the displayed second route"
cat > "$OUTPUT_LIST_FILE" <<'EOF_REORDERED'
Replacement One
Replacement Two
EOF_REORDERED
: > "$AUDIO_LOG"
run_context switch-output 2
[ "$(sed -n '1p' "$AUDIO_LOG")" = $'set\tDisplayed Two' ] \
  || fail "cached output index should resolve to its displayed name before any refresh"

run_cadence_case() {
  local scenario="$1"
  local expected="$2"
  local cadence_state="$TMP_DIR/cadence-$scenario"
  local pid=""
  rm -rf "$cadence_state"
  mkdir -p "$cadence_state"
  : > "$OSASCRIPT_LOG"

  env "${base_env[@]}" \
    "BARISTA_RUNTIME_CONTEXT_DIR=$cadence_state" \
    "BARISTA_RUNTIME_CONTEXT_HELPER_BIN=$BIN_DIR/runtime_context_helper" \
    "BARISTA_TEST_MEDIA_SCENARIO=$scenario" \
    BARISTA_RUNTIME_CONTEXT_INTERVAL=0.001 \
    BARISTA_RUNTIME_CONTEXT_MAX_ITERATIONS=7 \
    BARISTA_RUNTIME_CONTEXT_MEDIA_PLAYING_TICKS=1 \
    BARISTA_RUNTIME_CONTEXT_MEDIA_RUNNING_TICKS=2 \
    BARISTA_RUNTIME_CONTEXT_MEDIA_IDLE_TICKS=3 \
    "$SCRIPT" daemon >/dev/null 2>&1 &
  pid=$!

  for _ in {1..250}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.01
  done
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    fail "daemon should stop after BARISTA_RUNTIME_CONTEXT_MAX_ITERATIONS"
  fi
  wait "$pid" || fail "bounded daemon cadence fixture should exit successfully"
  stop_helpers

  local actual
  actual="$(grep -c '^media$' "$OSASCRIPT_LOG" || true)"
  [ "$actual" = "$expected" ] \
    || fail "$scenario cadence expected $expected media probes across 7 ticks, got $actual"
}

run_cadence_case playing 7
run_cadence_case paused 4
run_cadence_case none 3

printf 'test_runtime_context_media_efficiency.sh: ok\n'
