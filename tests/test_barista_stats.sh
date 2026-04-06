#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/bin/barista-stats.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s (missing=%s)\n' "$message" "$needle" >&2
    exit 1
  fi
}

printf '1775400000|reload|{"count":1}\n' > "$TMP_DIR/.barista_stats.log"

CONFIG_DIR="$TMP_DIR" "$SCRIPT" event smoke 12 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_build_time 412 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_menu_render_time 210 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_time 111 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_build_time 64 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_apply_time 47 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_front_app_time 23 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_triforce_time 19 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_spaces_time 6 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_control_center_time 15 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_left_layout_group_time 1 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_right_layout_time 77 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_right_layout_build_time 29 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_right_layout_apply_time 48 ok >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" event config_registry_time 14 ok >/dev/null
BARISTA_EVENT_META_JSON='{"strategy":"full_rebuild","added":3,"removed":0,"updated":3,"prepare_ms":20,"apply_ms":25,"discovery_ms":6,"build_ms":7,"decision_ms":7}' CONFIG_DIR="$TMP_DIR" "$SCRIPT" event space_topology_refresh 45 "spaces=3 strategy=full_rebuild" >/dev/null
BARISTA_EVENT_META_JSON='{"strategy":"incremental_add_remove","added":1,"removed":1,"updated":2}' CONFIG_DIR="$TMP_DIR" "$SCRIPT" event space_topology_refresh 18 "spaces=2 strategy=incremental_add_remove" >/dev/null
BARISTA_EVENT_META_JSON='{"strategy":"full_rebuild","spaces":3,"total_ms":90,"visual_call_ms":28}' CONFIG_DIR="$TMP_DIR" "$SCRIPT" event space_refresh_overhead 17 "spaces=3 strategy=full_rebuild total_ms=90 visual_call_ms=28" >/dev/null

if [ ! -f "$TMP_DIR/.barista_stats.log.legacy" ]; then
  echo "FAIL: legacy log should be preserved as .legacy" >&2
  exit 1
fi

event_count="$(jq -sr '[.[] | select(.event == "smoke")] | length' "$TMP_DIR/.barista_stats.log")"
assert_eq "$event_count" "1" "smoke event should be written as JSONL"

duration="$(jq -r 'select(.event == "smoke") | .duration_ms' "$TMP_DIR/.barista_stats.log")"
assert_eq "$duration" "12" "smoke event duration should round-trip"

CONFIG_DIR="$TMP_DIR" "$SCRIPT" reload >/dev/null
CONFIG_DIR="$TMP_DIR" "$SCRIPT" reload-time 25 >/dev/null

show_output="$(CONFIG_DIR="$TMP_DIR" "$SCRIPT" show)"
assert_contains "$show_output" "Total reloads: 1" "reload count should be reported"
assert_contains "$show_output" "Last reload time: 25ms" "reload duration should be reported"
assert_contains "$show_output" "Config build time: 1 (avg 412ms, last 412ms)" "config build summary should be reported"
assert_contains "$show_output" "menu render: 1 (avg 210ms, last 210ms)" "config menu render summary should be reported"
assert_contains "$show_output" "left layout: 1 (avg 111ms, last 111ms)" "config left layout summary should be reported"
assert_contains "$show_output" "build: 1 (avg 64ms, last 64ms)" "config left layout build summary should be reported"
assert_contains "$show_output" "apply: 1 (avg 47ms, last 47ms)" "config left layout apply summary should be reported"
assert_contains "$show_output" "front_app: 1 (avg 23ms, last 23ms)" "config left layout front_app summary should be reported"
assert_contains "$show_output" "triforce: 1 (avg 19ms, last 19ms)" "config left layout triforce summary should be reported"
assert_contains "$show_output" "spaces: 1 (avg 6ms, last 6ms)" "config left layout spaces summary should be reported"
assert_contains "$show_output" "control_center: 1 (avg 15ms, last 15ms)" "config left layout control_center summary should be reported"
assert_contains "$show_output" "group: 1 (avg 1ms, last 1ms)" "config left layout group summary should be reported"
assert_contains "$show_output" "right layout: 1 (avg 77ms, last 77ms)" "config right layout summary should be reported"
assert_contains "$show_output" "build: 1 (avg 29ms, last 29ms)" "config right layout build summary should be reported"
assert_contains "$show_output" "apply: 1 (avg 48ms, last 48ms)" "config right layout apply summary should be reported"
assert_contains "$show_output" "registry: 1 (avg 14ms, last 14ms)" "config registry summary should be reported"
assert_contains "$show_output" "Space topology refreshes: 2 (avg 31.5ms, last 18ms)" "topology summary should be reported"
assert_contains "$show_output" "full_rebuild: 1 (avg 45ms, last 45ms)" "full rebuild strategy should be broken out"
assert_contains "$show_output" "incremental_add_remove: 1 (avg 18ms, last 18ms)" "incremental add/remove strategy should be broken out"
assert_contains "$show_output" "prepare: 1 (avg 20ms, last 20ms)" "full rebuild prepare phase should be summarized"
assert_contains "$show_output" "apply: 1 (avg 25ms, last 25ms)" "full rebuild apply phase should be summarized"
assert_contains "$show_output" "discovery: 1 (avg 6ms, last 6ms)" "full rebuild discovery phase should be summarized"
assert_contains "$show_output" "build: 1 (avg 7ms, last 7ms)" "full rebuild build phase should be summarized"
assert_contains "$show_output" "decision: 1 (avg 7ms, last 7ms)" "full rebuild decision phase should be summarized"
assert_contains "$show_output" "Space refresh overhead: 1 (avg 17ms, last 17ms)" "space refresh overhead summary should be reported"

printf 'test_barista_stats.sh: ok\n'
