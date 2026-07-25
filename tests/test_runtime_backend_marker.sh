#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
FAIL_LOG="$TMP_DIR/failures.log"
MARKER="$CONFIG_DIR/.barista_runtime_backend"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR"
: > "$FAIL_LOG"

publish() {
  local mode="$1"
  lua - "$ROOT_DIR" "$CONFIG_DIR" "$mode" <<'LUA'
local root, config_dir, mode = ...
package.path = table.concat({
  package.path,
  root .. "/modules/?.lua",
}, ";")
local resolver = require("binary_resolver")
local ok, err = resolver.publish_resolved_runtime_backend(config_dir, mode)
if not ok then
  io.stderr:write(tostring(err), "\n")
  os.exit(1)
end
LUA
}

pids=()
for index in $(seq 1 80); do
  mode="lua"
  if [ $((index % 2)) -eq 0 ]; then
    mode="compiled"
  fi
  (publish "$mode" 2>> "$FAIL_LOG") &
  pids+=("$!")
done

while :; do
  live=0
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      live=1
      break
    fi
  done

  if [ -f "$MARKER" ]; then
    marker_value="$(cat "$MARKER")"
    case "$marker_value" in
      lua|compiled) ;;
      *)
        echo "FAIL: concurrent readers observed a partial runtime marker: $marker_value" >&2
        exit 1
        ;;
    esac
  fi
  [ "$live" -eq 1 ] || break
done

for pid in "${pids[@]}"; do
  wait "$pid" || {
    cat "$FAIL_LOG" >&2
    echo "FAIL: concurrent runtime marker publisher failed" >&2
    exit 1
  }
done

[ ! -s "$FAIL_LOG" ] || {
  cat "$FAIL_LOG" >&2
  echo "FAIL: concurrent runtime marker publisher logged an error" >&2
  exit 1
}
case "$(cat "$MARKER")" in
  lua|compiled) ;;
  *)
    echo "FAIL: final runtime marker is incomplete" >&2
    exit 1
    ;;
esac
if find "$CONFIG_DIR" -maxdepth 1 -name '.barista_runtime_backend.*.tmp' -print -quit | grep -q .; then
  echo "FAIL: runtime marker publication left a temporary file" >&2
  exit 1
fi

printf 'test_runtime_backend_marker.sh: ok\n'
