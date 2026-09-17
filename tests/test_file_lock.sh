#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/file_lock.c"
CC_BIN="${CC:-$(command -v cc 2>/dev/null || true)}"
TMP_DIR="$(mktemp -d)"
BIN="$TMP_DIR/file_lock"
LOCK_FILE="$TMP_DIR/lock"

cleanup() {
  exec 8>&- 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_status() {
  local expected="$1"
  shift
  local actual=0

  "$@" || actual=$?
  [ "$actual" -eq "$expected" ] ||
    fail "expected status $expected, got $actual: $*"
}

[ -n "$CC_BIN" ] || fail "a C compiler is required"

"$CC_BIN" -std=c99 -Wall -Wextra -Werror "$SOURCE" -o "$BIN"

expect_status 64 "$BIN"
expect_status 64 "$BIN" 9 extra
expect_status 64 "$BIN" 9 0 extra
expect_status 64 "$BIN" not-a-fd
expect_status 64 "$BIN" 9 -1
expect_status 64 "$BIN" 9 1.5
expect_status 64 "$BIN" 9 60001
expect_status 74 "$BIN" 2147483647
expect_status 74 "$BIN" 2147483647 1000

# The child locks the parent's inherited open file description. Its lock must
# remain held after the child exits because the parent still owns descriptor 9.
exec 9>"$LOCK_FILE"
expect_status 0 "$BIN" 9

# A separately opened descriptor must observe contention while descriptor 9
# remains open in the parent.
exec 8>"$LOCK_FILE"
expect_status 75 "$BIN" 8
expect_status 75 "$BIN" 8 0

# Closing the parent's inherited descriptor releases the lock, allowing the
# previously contended descriptor to acquire it.
exec 9>&-
expect_status 0 "$BIN" 8

# Bounded waits must retain the same inherited-descriptor ownership as the
# original nonblocking form, without a worker or a lock surviving its owner.
python3 - "$BIN" "$LOCK_FILE.wait" <<'PY'
import fcntl
import os
import signal
import subprocess
import sys
import threading
import time

binary, path = sys.argv[1:]
holder = os.open(path, os.O_CREAT | os.O_WRONLY, 0o600)
waiter = os.open(path, os.O_WRONLY)
fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)

try:
    started = time.monotonic()
    result = subprocess.run([binary, str(waiter), "40"], pass_fds=(waiter,), timeout=1)
    elapsed = time.monotonic() - started
    assert result.returncode == 75, result.returncode
    assert 0.03 <= elapsed < 0.5, elapsed

    released = []
    def release_holder():
        fcntl.flock(holder, fcntl.LOCK_UN)
        released.append(time.monotonic())

    timer = threading.Timer(0.04, release_holder)
    timer.start()
    started = time.monotonic()
    result = subprocess.run([binary, str(waiter), "1000"], pass_fds=(waiter,), timeout=2)
    timer.join()
    assert result.returncode == 0, result.returncode
    assert released and started < released[0] <= time.monotonic(), released

    # The helper has exited, but the original waiter descriptor still owns it.
    try:
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        pass
    else:
        raise AssertionError("timed acquisition did not retain the parent's lock")
    os.close(waiter)
    waiter = os.open(path, os.O_WRONLY)
    fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)

    # Terminating a blocked helper must not leave a hidden waiter behind.
    process = subprocess.Popen([binary, str(waiter), "1000"], pass_fds=(waiter,))
    time.sleep(0.02)
    process.terminate()
    assert process.wait(timeout=1) == -signal.SIGTERM
    fcntl.flock(holder, fcntl.LOCK_UN)
    result = subprocess.run([binary, str(waiter)], pass_fds=(waiter,), timeout=1)
    assert result.returncode == 0, result.returncode
finally:
    os.close(waiter)
    os.close(holder)
PY

printf 'test_file_lock.sh: ok\n'
