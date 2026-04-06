#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/app_icon.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
ICON_MAP="$CONFIG_DIR/icon_map.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR"

assert_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_equal "ghostty alias" "" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" Ghostty)"
assert_equal "ghostty lowercase alias" "" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" ghostty)"
assert_equal "oracle manager gui alias" "󰯙" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" oracle_manager_gui)"
assert_equal "oracle agent manager alias" "󰯙" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" "Oracle Agent Manager")"
assert_equal "cursor alias" "󰨞" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" Cursor)"
assert_equal "lm studio alias" "󰭻" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" "LM Studio")"

printf '{"Claude":"AI"}\n' > "$ICON_MAP"
assert_equal "custom icon override" "AI" "$(BARISTA_CONFIG_DIR="$CONFIG_DIR" ICON_MAP="$ICON_MAP" "$SCRIPT" Claude)"

printf 'test_app_icon.sh: ok\n'
