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
EVENT_HELPER="$TMP_DIR/runtime_context_helper_events"
WAIT_POLICY_HELPER="$TMP_DIR/runtime_context_helper_wait_policy"
MONOTONIC_HELPER="$TMP_DIR/monotonic_now"
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

cat > "$TMP_DIR/runtime_context_helper_events.m" <<EOF
#define main barista_runtime_context_helper_main
#include "$SOURCE"
#undef main

static NSUInteger test_query_count(NSString *path) {
  NSString *queryLog = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
  if (queryLog.length == 0) {
    return 0;
  }
  return [queryLog componentsSeparatedByString:@"\n"].count - 1;
}

int main(void) {
  @autoreleasepool {
    NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
    [NSThread detachNewThreadWithBlock:^{
      @autoreleasepool {
        NSString *queryLogPath = NSProcessInfo.processInfo.environment[@"BARISTA_TEST_YABAI_LOG"];
        NSString *stateDirectory = NSProcessInfo.processInfo.environment[@"BARISTA_RUNTIME_CONTEXT_DIR"];
        NSString *cachePath = [stateDirectory stringByAppendingPathComponent:@"front_app.tsv"];
        for (NSUInteger attempt = 0; attempt < 200; attempt++) {
          if (test_query_count(queryLogPath) >= 2 &&
              [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            break;
          }
          [NSThread sleepForTimeInterval:0.01];
        }
        NSString *timingPath = NSProcessInfo.processInfo.environment[@"BARISTA_TEST_EVENT_TIMING_LOG"];
        NSString *eventTime = [NSString stringWithFormat:@"%.9f\n", monotonic_seconds()];
        [eventTime writeToFile:timingPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *scenario = NSProcessInfo.processInfo.environment[@"BARISTA_TEST_EVENT_SCENARIO"];
        NSUInteger eventCount = 0;
        if ([scenario isEqualToString:@"maximum-deferral"]) {
          for (NSUInteger attempt = 0; attempt < 20; attempt++) {
            NSString *name = attempt % 2 == 0
                ? NSWorkspaceDidActivateApplicationNotification
                : NSWorkspaceActiveSpaceDidChangeNotification;
            [center postNotificationName:name object:nil];
            eventCount++;
            [NSThread sleepForTimeInterval:0.04];
            if (test_query_count(queryLogPath) >= 3) {
              break;
            }
          }
        } else {
          NSString *name = NSWorkspaceDidActivateApplicationNotification;
          if ([scenario isEqualToString:@"space"]) {
            name = NSWorkspaceActiveSpaceDidChangeNotification;
          } else if ([scenario isEqualToString:@"wake"]) {
            name = NSWorkspaceDidWakeNotification;
          }
          [center postNotificationName:name object:nil];
          eventCount = 1;
        }
        NSString *eventCountPath = NSProcessInfo.processInfo.environment[@"BARISTA_TEST_EVENT_COUNT_LOG"];
        [[NSString stringWithFormat:@"%lu\n", (unsigned long)eventCount]
            writeToFile:eventCountPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        for (NSUInteger attempt = 0; attempt < 200; attempt++) {
          if (test_query_count(queryLogPath) >= 4) {
            break;
          }
          [NSThread sleepForTimeInterval:0.01];
        }
        kill(getpid(), SIGTERM);
      }
    }];
    return daemon_loop_with_notification_center(center);
  }
}
EOF
"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Cocoa \
  -framework Foundation \
  "$TMP_DIR/runtime_context_helper_events.m" \
  -o "$EVENT_HELPER"

cat > "$TMP_DIR/runtime_context_helper_wait_policy.m" <<EOF
#define main barista_runtime_context_helper_main
#include "$SOURCE"
#undef main

int main(void) {
  @autoreleasepool {
    if (task_poll_interval_seconds(0.0) != kTaskFastPollIntervalSeconds ||
        task_poll_interval_seconds(kTaskFastPollWindowSeconds / 2.0) != kTaskFastPollIntervalSeconds ||
        task_poll_interval_seconds(kTaskFastPollWindowSeconds) != kTaskSettledPollIntervalSeconds ||
        task_poll_interval_seconds(kTaskFastPollWindowSeconds * 2.0) != kTaskSettledPollIntervalSeconds) {
      return 1;
    }
    return 0;
  }
}
EOF
"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Cocoa \
  -framework Foundation \
  "$TMP_DIR/runtime_context_helper_wait_policy.m" \
  -o "$WAIT_POLICY_HELPER"
"$WAIT_POLICY_HELPER"

cat > "$TMP_DIR/monotonic_now.c" <<'EOF'
#include <stdio.h>
#include <time.h>

int main(void) {
  struct timespec timestamp = {0};
  if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) {
    return 1;
  }
  printf("%.9f\n", (double)timestamp.tv_sec + (double)timestamp.tv_nsec / 1000000000.0);
  return 0;
}
EOF
"$CC_BIN" -Wall -Wextra -Werror \
  "$TMP_DIR/monotonic_now.c" \
  -o "$MONOTONIC_HELPER"

mkdir -p "$TMP_DIR/home"

# A query that ignores TERM must still be killed after the existing timeout
# grace period. This keeps the adaptive early polling change isolated from the
# established timeout/termination contract.
TIMEOUT_YABAI="$TMP_DIR/timeout-yabai"
TIMEOUT_PID_LOG="$TMP_DIR/timeout-yabai.pids"
cat > "$TMP_DIR/timeout-yabai.c" <<'EOF'
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void) {
  const char *path = getenv("BARISTA_TEST_TIMEOUT_PID_LOG");
  if (path == NULL) {
    return 1;
  }
  signal(SIGTERM, SIG_IGN);
  int descriptor = open(path, O_WRONLY | O_APPEND);
  if (descriptor < 0) {
    return 1;
  }
  dprintf(descriptor, "%d\n", getpid());
  close(descriptor);
  while (1) {
    pause();
  }
}
EOF
"$CC_BIN" -Wall -Wextra -Werror \
  "$TMP_DIR/timeout-yabai.c" \
  -o "$TIMEOUT_YABAI"

: > "$TIMEOUT_PID_LOG"
env -i \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOME="$TMP_DIR/home" \
  BARISTA_RUNTIME_CONTEXT_DIR="$TMP_DIR/timeout-state" \
  BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME="Finder" \
  BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT="0.02" \
  BARISTA_TEST_TIMEOUT_PID_LOG="$TIMEOUT_PID_LOG" \
  BARISTA_YABAI_BIN="$TIMEOUT_YABAI" \
  "$HELPER" refresh-front-app
python3 - "$TIMEOUT_PID_LOG" <<'PY'
import os
from pathlib import Path
import sys

pids = [int(value) for value in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()]
assert pids, pids
survivors = []
for pid in pids:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        continue
    survivors.append(pid)
assert not survivors, survivors
PY

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
if [[ -n "${BARISTA_TEST_YABAI_TIME_LOG:-}" ]]; then
  timestamp="$("${BARISTA_TEST_MONOTONIC_BIN:?}")"
  printf '%s\t%s\n' "$timestamp" "$*" >> "$BARISTA_TEST_YABAI_TIME_LOG"
fi
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
  local helper_command="${4:-refresh-front-app}"
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
  env -i "${environment[@]}" "$HELPER" "$helper_command"
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
run_query_case match "$TMP_DIR/query-fresh" "" fresh-front-app > "$TMP_DIR/query-fresh-output.tsv"
assert_query_total 2
assert_query_count '-m query --windows --window' 1
assert_query_count '-m query --spaces' 1
assert_query_count '-m query --windows' 0
cmp -s "$TMP_DIR/query-fresh/front_app.tsv" "$TMP_DIR/query-fresh-output.tsv" || {
  echo "FAIL: fresh-front-app should return the exact snapshot it publishes" >&2
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

# Each notification source schedules a serialized refresh, and a sustained
# sub-debounce stream must still flush once the 250 ms cap is reached.
run_event_case() {
  local scenario="$1"
  local maximum_latency="$2"
  local minimum_events="$3"
  local case_dir="$TMP_DIR/query-events-$scenario"
  local query_log="$case_dir/queries.log"
  local query_time_log="$case_dir/query-time.log"
  local event_time_log="$case_dir/event-time.log"
  local event_count_log="$case_dir/event-count.log"
  mkdir -p "$case_dir"
  : > "$query_log"
  : > "$query_time_log"

  python3 - "$EVENT_HELPER" "$case_dir/state" "$TMP_DIR/home" "$QUERY_YABAI" \
    "$query_log" "$event_time_log" "$query_time_log" "$event_count_log" \
    "$scenario" "$MONOTONIC_HELPER" <<'PY'
import os
import subprocess
import sys

(
    helper,
    state_dir,
    home,
    yabai,
    query_log,
    event_log,
    query_time_log,
    event_count_log,
    scenario,
    monotonic_bin,
) = sys.argv[1:]
env = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": home,
    "BARISTA_RUNTIME_CONTEXT_DIR": state_dir,
    "BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME": "Cursor",
    "BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL": "5",
    "BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT": "0.2",
    "BARISTA_TEST_YABAI_LOG": query_log,
    "BARISTA_TEST_YABAI_TIME_LOG": query_time_log,
    "BARISTA_TEST_MONOTONIC_BIN": monotonic_bin,
    "BARISTA_TEST_EVENT_TIMING_LOG": event_log,
    "BARISTA_TEST_EVENT_COUNT_LOG": event_count_log,
    "BARISTA_TEST_EVENT_SCENARIO": scenario,
    "BARISTA_TEST_YABAI_SCENARIO": "match",
    "BARISTA_YABAI_BIN": yabai,
}
subprocess.run([helper], env=env, check=True, timeout=4)
PY

  python3 - "$query_log" "$event_time_log" "$query_time_log" \
    "$event_count_log" "$maximum_latency" "$minimum_events" <<'PY'
from pathlib import Path
import sys

query_log, event_log, query_time_log, event_count_log, maximum, minimum = sys.argv[1:]
commands = Path(query_log).read_text(encoding="utf-8").splitlines()
assert commands == [
    "-m query --windows --window",
    "-m query --spaces",
    "-m query --windows --window",
    "-m query --spaces",
], commands
event_time = float(Path(event_log).read_text(encoding="utf-8").strip())
query_rows = Path(query_time_log).read_text(encoding="utf-8").splitlines()
assert len(query_rows) == 4, query_rows
event_query_time = float(query_rows[2].split("\t", 1)[0])
latency = event_query_time - event_time
assert 0.0 <= latency < float(maximum), latency
event_count = int(Path(event_count_log).read_text(encoding="utf-8").strip())
assert event_count >= int(minimum), event_count
PY
}

run_event_case activation 0.40 1
run_event_case space 0.40 1
run_event_case wake 0.40 1
run_event_case maximum-deferral 0.45 5

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
  BARISTA_RUNTIME_CONTEXT_FRONT_APP_SAFETY_INTERVAL="0.05" \
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
