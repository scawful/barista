#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test_runtime_context_helper_publication.sh: skipped (Darwin only)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/runtime_context_helper.m"
TMP_DIR="$(mktemp -d)"
HELPER="$TMP_DIR/runtime_context_helper"
STATE_DIR="$TMP_DIR/runtime_context"
CACHE_FILE="$STATE_DIR/front_app.tsv"
DAEMON_PID=""

cleanup() {
  if [[ -n "$DAEMON_PID" ]]; then
    kill "$DAEMON_PID" >/dev/null 2>&1 || true
    wait "$DAEMON_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [[ -z "$CC_BIN" ]]; then
  printf 'test_runtime_context_helper_publication.sh: skipped (Objective-C compiler unavailable)\n'
  exit 0
fi

"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Cocoa \
  -framework Foundation \
  "$SOURCE" \
  -o "$HELPER"

mkdir -p "$TMP_DIR/home"

run_refresh() {
  local app_name="${1:-Finder}"
  env -i \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP_DIR/home" \
    BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
    BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME="$app_name" \
    BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT="0.2" \
    BARISTA_YABAI_BIN="/usr/bin/false" \
    "$HELPER" refresh-front-app
}

file_identity() {
  python3 - "$1" <<'PY'
import os
import sys

stat = os.stat(sys.argv[1], follow_symlinks=False)
print(f"{stat.st_ino}:{stat.st_mtime_ns}")
PY
}

assert_exact_cache() {
  local expected="$1"
  cmp -s "$expected" "$CACHE_FILE" || {
    echo "FAIL: front-app cache bytes did not match the expected snapshot" >&2
    exit 1
  }
}

# The common native path shares one focused-window snapshot across app naming
# and matching; fallback still performs one full-window query when needed.
QUERY_YABAI="$TMP_DIR/query-yabai"
QUERY_LOG="$TMP_DIR/query-yabai.log"
cat > "$QUERY_YABAI" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "${BARISTA_TEST_YABAI_LOG:?}"
case "$*" in
  '-m query --spaces')
    printf '%s\n' '[{"index":3,"display":1,"type":"bsp","is-visible":true,"has-focus":true}]'
    ;;
  '-m query --windows --window')
    printf '%s\n' '{"id":7,"app":"Cursor","space":3,"display":1,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"is-native-fullscreen":false,"layer":"normal","sub-layer":"auto","is-minimized":false}'
    ;;
  '-m query --windows')
    if [[ "${BARISTA_TEST_YABAI_SCENARIO:-match}" == "fallback" ]]; then
      printf '%s\n' '[{"id":9,"app":"Finder","space":3,"display":1,"has-focus":false,"is-floating":true,"is-sticky":false,"has-fullscreen-zoom":false,"is-native-fullscreen":false,"layer":"normal","sub-layer":"auto","is-minimized":false}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$QUERY_YABAI"

run_query_case() {
  local scenario="$1"
  local case_state_dir="$2"
  local app_override="${3:-}"
  local -a environment=(
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    "HOME=$TMP_DIR/home"
    "BARISTA_RUNTIME_CONTEXT_DIR=$case_state_dir"
    "BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT=0.2"
    "BARISTA_TEST_YABAI_LOG=$QUERY_LOG"
    "BARISTA_TEST_YABAI_SCENARIO=$scenario"
    "BARISTA_YABAI_BIN=$QUERY_YABAI"
  )
  if [[ -n "$app_override" ]]; then
    environment+=("BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME=$app_override")
  fi
  env -i "${environment[@]}" "$HELPER" refresh-front-app
}

assert_query_count() {
  local command="$1"
  local expected="$2"
  local actual
  actual="$(awk -v command="$command" '$0 == command { count++ } END { print count + 0 }' "$QUERY_LOG")"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected $expected '$command' queries, got $actual" >&2
    cat "$QUERY_LOG" >&2
    exit 1
  }
}

assert_query_total() {
  local expected="$1"
  local actual
  actual="$(awk 'END { print NR + 0 }' "$QUERY_LOG")"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected $expected total yabai queries, got $actual" >&2
    cat "$QUERY_LOG" >&2
    exit 1
  }
}

: > "$QUERY_LOG"
run_query_case match "$TMP_DIR/query-match"
assert_query_total 2
assert_query_count '-m query --windows --window' 1
assert_query_count '-m query --spaces' 1
assert_query_count '-m query --windows' 0
grep -Fxq $'app_name\tCursor' "$TMP_DIR/query-match/front_app.tsv" || {
  echo "FAIL: the shared focused-window snapshot should drive the common match" >&2
  exit 1
}
grep -Fxq $'window_available\ttrue' "$TMP_DIR/query-match/front_app.tsv" || {
  echo "FAIL: the shared focused-window snapshot should remain managed" >&2
  exit 1
}

: > "$QUERY_LOG"
run_query_case fallback "$TMP_DIR/query-fallback" Finder
assert_query_total 3
assert_query_count '-m query --windows --window' 1
assert_query_count '-m query --spaces' 1
assert_query_count '-m query --windows' 1
grep -Fxq $'app_name\tFinder' "$TMP_DIR/query-fallback/front_app.tsv" || {
  echo "FAIL: a focused mismatch should retain full-window fallback selection" >&2
  exit 1
}
grep -Fxq $'window_available\ttrue' "$TMP_DIR/query-fallback/front_app.tsv" || {
  echo "FAIL: full-window fallback should remain managed" >&2
  exit 1
}
grep -Fxq $'state_label\tFloating · Managed Space' "$TMP_DIR/query-fallback/front_app.tsv" || {
  echo "FAIL: full-window fallback should publish the selected Finder state" >&2
  exit 1
}

# A missing target is created with the deterministic eight-row UTF-8 schema.
run_refresh Finder
[[ -f "$CACHE_FILE" && ! -L "$CACHE_FILE" ]] || {
  echo "FAIL: refresh-front-app should create a regular cache file" >&2
  exit 1
}
python3 - "$CACHE_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
raw = path.read_bytes()
assert raw.endswith(b"\n"), raw
assert b"\0" not in raw, raw
rows = [line.split("\t", 1) for line in raw.decode("utf-8").splitlines()]
assert rows == [
    ["app_name", "Finder"],
    ["window_available", "false"],
    ["state_icon", "󰋽"],
    ["state_label", "No managed window"],
    ["location_label", "Space ? · Display ?"],
    ["space_index", ""],
    ["display_index", ""],
    ["space_visible", "false"],
], rows
PY
cp "$CACHE_FILE" "$TMP_DIR/finder.tsv"

# Identical snapshots retain both inode and nanosecond modification time.
finder_identity_before="$(file_identity "$CACHE_FILE")"
run_refresh Finder
finder_identity_after="$(file_identity "$CACHE_FILE")"
[[ "$finder_identity_before" == "$finder_identity_after" ]] || {
  echo "FAIL: unchanged front-app content should preserve inode and mtime" >&2
  exit 1
}

# A real content change still publishes through atomic replacement.
run_refresh Cursor
cursor_identity="$(file_identity "$CACHE_FILE")"
[[ "$cursor_identity" != "$finder_identity_after" ]] || {
  echo "FAIL: changed front-app content should replace the cache identity" >&2
  exit 1
}
grep -Fxq $'app_name\tCursor' "$CACHE_FILE" || {
  echo "FAIL: changed front-app content was not published" >&2
  exit 1
}
cp "$CACHE_FILE" "$TMP_DIR/cursor.tsv"

run_refresh Cursor
[[ "$cursor_identity" == "$(file_identity "$CACHE_FILE")" ]] || {
  echo "FAIL: the changed snapshot should become the new stable identity" >&2
  exit 1
}

# Prefix-equal binary corruption and oversized suffixes must never compare equal.
python3 - "$TMP_DIR/cursor.tsv" "$CACHE_FILE" <<'PY'
from pathlib import Path
import sys

expected = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(expected + b"\0JUNK")
PY
corrupt_identity="$(file_identity "$CACHE_FILE")"
run_refresh Cursor
assert_exact_cache "$TMP_DIR/cursor.tsv"
[[ "$corrupt_identity" != "$(file_identity "$CACHE_FILE")" ]] || {
  echo "FAIL: NUL-suffixed cache corruption should be atomically repaired" >&2
  exit 1
}

python3 - "$TMP_DIR/cursor.tsv" "$CACHE_FILE" <<'PY'
from pathlib import Path
import sys

expected = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(expected + (b"x" * (128 * 1024)))
PY
run_refresh Cursor
assert_exact_cache "$TMP_DIR/cursor.tsv"

# Equal-content symlinks and FIFOs are repaired without trusting or blocking on them.
mv "$CACHE_FILE" "$TMP_DIR/prior-cache.tsv"
cp "$TMP_DIR/cursor.tsv" "$TMP_DIR/external.tsv"
ln -s "$TMP_DIR/external.tsv" "$CACHE_FILE"
run_refresh Cursor
[[ -f "$CACHE_FILE" && ! -L "$CACHE_FILE" ]] || {
  echo "FAIL: an equal-content symlink should be replaced with a regular cache" >&2
  exit 1
}
assert_exact_cache "$TMP_DIR/cursor.tsv"
cmp -s "$TMP_DIR/cursor.tsv" "$TMP_DIR/external.tsv" || {
  echo "FAIL: repairing a symlink should not modify its external target" >&2
  exit 1
}

mv "$CACHE_FILE" "$TMP_DIR/post-symlink-cache.tsv"
mkfifo "$CACHE_FILE"
python3 - "$HELPER" "$STATE_DIR" "$TMP_DIR/home" <<'PY'
import os
import subprocess
import sys

helper, state_dir, home = sys.argv[1:]
env = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": home,
    "BARISTA_RUNTIME_CONTEXT_DIR": state_dir,
    "BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME": "Cursor",
    "BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT": "0.2",
    "BARISTA_YABAI_BIN": "/usr/bin/false",
}
subprocess.run([helper, "refresh-front-app"], env=env, check=True, timeout=2)
PY
[[ -f "$CACHE_FILE" && ! -p "$CACHE_FILE" ]] || {
  echo "FAIL: a FIFO cache should be replaced without blocking" >&2
  exit 1
}
assert_exact_cache "$TMP_DIR/cursor.tsv"

# Directory targets, including symlinks to directories, fail closed and remain intact.
mv "$CACHE_FILE" "$TMP_DIR/post-fifo-cache.tsv"
mkdir "$CACHE_FILE"
touch "$CACHE_FILE/sentinel"
if run_refresh Cursor; then
  echo "FAIL: a directory cache target should be rejected" >&2
  exit 1
fi
[[ -d "$CACHE_FILE" && -f "$CACHE_FILE/sentinel" ]] || {
  echo "FAIL: rejecting a directory target should preserve it" >&2
  exit 1
}
mv "$CACHE_FILE" "$TMP_DIR/cache-directory"
mkdir "$TMP_DIR/linked-directory"
touch "$TMP_DIR/linked-directory/sentinel"
ln -s "$TMP_DIR/linked-directory" "$CACHE_FILE"
if run_refresh Cursor; then
  echo "FAIL: a symlink-to-directory cache target should be rejected" >&2
  exit 1
fi
[[ -L "$CACHE_FILE" && -f "$TMP_DIR/linked-directory/sentinel" ]] || {
  echo "FAIL: rejecting a directory symlink should preserve it and its target" >&2
  exit 1
}

# A dangling link is safe to replace, and the real daemon keeps its stable cache warm.
unlink "$CACHE_FILE"
ln -s "$TMP_DIR/missing-target.tsv" "$CACHE_FILE"
run_refresh Cursor
[[ -f "$CACHE_FILE" && ! -L "$CACHE_FILE" ]] || {
  echo "FAIL: a dangling cache symlink should be repaired" >&2
  exit 1
}
assert_exact_cache "$TMP_DIR/cursor.tsv"

env -i \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOME="$TMP_DIR/home" \
  BARISTA_RUNTIME_CONTEXT_DIR="$STATE_DIR" \
  BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME="Cursor" \
  BARISTA_RUNTIME_CONTEXT_INTERVAL="0.05" \
  BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT="0.2" \
  BARISTA_YABAI_BIN="/usr/bin/false" \
  "$HELPER" daemon >/dev/null 2>&1 &
DAEMON_PID=$!

daemon_identity="$(file_identity "$CACHE_FILE")"
sleep 0.35
kill -0 "$DAEMON_PID" >/dev/null 2>&1 || {
  echo "FAIL: runtime context helper daemon exited unexpectedly" >&2
  exit 1
}
[[ "$daemon_identity" == "$(file_identity "$CACHE_FILE")" ]] || {
  echo "FAIL: unchanged daemon ticks should preserve cache identity" >&2
  exit 1
}

kill "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""
stopped_identity="$(file_identity "$CACHE_FILE")"
sleep 0.15
[[ "$stopped_identity" == "$(file_identity "$CACHE_FILE")" ]] || {
  echo "FAIL: a stopped helper daemon should not publish later writes" >&2
  exit 1
}

printf 'test_runtime_context_helper_publication.sh: ok\n'
