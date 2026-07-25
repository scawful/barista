#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/perf_clock.c"
CC_BIN="${CC:-$(command -v cc 2>/dev/null || true)}"
TMP_DIR="$(mktemp -d)"
BIN="$TMP_DIR/perf_clock"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

[ -n "$CC_BIN" ] || {
  echo "FAIL: a C compiler is required" >&2
  exit 1
}

"$CC_BIN" -std=c99 -Wall -Wextra -Werror "$SOURCE" -o "$BIN"

before_seconds="$(date +%s)"
first="$("$BIN")"
second="$("$BIN")"
after_seconds="$(date +%s)"

case "$first:$second" in
  *[!0-9:]*|:*)
    echo "FAIL: perf_clock must print numeric epoch milliseconds" >&2
    exit 1
    ;;
esac

for reading in "$first" "$second"; do
  native_seconds=$((reading / 1000))
  [ "$native_seconds" -ge $((before_seconds - 1)) ] \
    && [ "$native_seconds" -le $((after_seconds + 1)) ] || {
      echo "FAIL: perf_clock must preserve realtime epoch semantics" >&2
      exit 1
    }
done

printf 'test_perf_clock.sh: ok\n'
