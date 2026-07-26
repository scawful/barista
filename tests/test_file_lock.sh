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
expect_status 64 "$BIN" not-a-fd
expect_status 74 "$BIN" 2147483647

# The child locks the parent's inherited open file description. Its lock must
# remain held after the child exits because the parent still owns descriptor 9.
exec 9>"$LOCK_FILE"
expect_status 0 "$BIN" 9

# A separately opened descriptor must observe contention while descriptor 9
# remains open in the parent.
exec 8>"$LOCK_FILE"
expect_status 75 "$BIN" 8

# Closing the parent's inherited descriptor releases the lock, allowing the
# previously contended descriptor to acquire it.
exec 9>&-
expect_status 0 "$BIN" 8

printf 'test_file_lock.sh: ok\n'
