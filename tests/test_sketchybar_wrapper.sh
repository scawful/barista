#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WRAPPER="$ROOT_DIR/bin/sketchybar_wrapper.sh"
CONFIG_DIR="$TMP_DIR/config"
mkdir -p "$CONFIG_DIR"
: > "$CONFIG_DIR/sketchybarrc"

for name in fork stock; do
  cat > "$TMP_DIR/$name" <<EOF
#!/bin/bash
echo "$name \$*"
EOF
  chmod +x "$TMP_DIR/$name"
done

run_wrapper() {
  env -u SKETCHYBAR_BIN BARISTA_CONFIG_DIR="$CONFIG_DIR" \
    SKETCHYBAR_ERR_LOG="$TMP_DIR/err.log" "$@" "$WRAPPER"
}

output="$(run_wrapper BARISTA_SKETCHYBAR_FORK_BIN="$TMP_DIR/fork")"
[ "$output" = "fork --config $CONFIG_DIR/sketchybarrc" ] || {
  echo "FAIL: an installed fork binary must be preferred, got: $output" >&2; exit 1;
}

output="$(run_wrapper BARISTA_SKETCHYBAR_FORK_BIN="$TMP_DIR/fork" SKETCHYBAR_BIN="$TMP_DIR/stock")"
[ "$output" = "stock --config $CONFIG_DIR/sketchybarrc" ] || {
  echo "FAIL: an explicit SKETCHYBAR_BIN must win over the fork, got: $output" >&2; exit 1;
}

echo "test_sketchybar_wrapper.sh: ok"
