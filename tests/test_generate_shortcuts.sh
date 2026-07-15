#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SKHD_OUTPUT="$TMP_DIR/barista_shortcuts.conf"
WORKFLOW_OUTPUT="$TMP_DIR/workflow_shortcuts.json"
SECOND_OUTPUT="$TMP_DIR/workflow_shortcuts.second.json"
LOCAL_WORKFLOW="$TMP_DIR/workflow_shortcuts.local.json"
LOCAL_OUTPUT="$TMP_DIR/workflow_shortcuts.with-local.json"

BARISTA_CONFIG_DIR="$ROOT_DIR" lua "$ROOT_DIR/helpers/generate_shortcuts.lua" \
  "$SKHD_OUTPUT" "$WORKFLOW_OUTPUT" >/dev/null

jq -e '.generated.source == "modules/shortcuts.lua"' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.generated | has("supplement") | not' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.keymap[0].section == "Barista (generated)"' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.keymap[0].source == "modules/shortcuts.lua"' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.keymap | length == 1' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.actions | length == 0' "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.docs | length == 0' "$WORKFLOW_OUTPUT" >/dev/null

expected_count=$(BARISTA_CONFIG_DIR="$ROOT_DIR" lua - <<'LUA'
local root = assert(os.getenv("BARISTA_CONFIG_DIR"))
package.path = package.path .. ";" .. root .. "/modules/?.lua"
print(#require("shortcuts").list_declared())
LUA
)
actual_count=$(jq '.keymap[0].items | length' "$WORKFLOW_OUTPUT")
[ "$actual_count" -eq "$expected_count" ] || {
  echo "FAIL: workflow shortcut count $actual_count != Lua count $expected_count" >&2
  exit 1
}

unique_count=$(jq '[.keymap[0].items[].keys] | unique | length' "$WORKFLOW_OUTPUT")
[ "$unique_count" -eq "$expected_count" ] || {
  echo "FAIL: duplicate generated workflow shortcut keys" >&2
  exit 1
}

jq -e '.keymap[0].items[] | select(.action == "open_task_focus" and .keys == "⌘⌥D")' \
  "$WORKFLOW_OUTPUT" >/dev/null
grep -Fq 'cmd + alt - d :' "$SKHD_OUTPUT"

cat >"$LOCAL_WORKFLOW" <<'JSON'
{
  "keymap": [
    {
      "section": "Local Tools",
      "items": [
        { "keys": "local", "description": "Machine-local shortcut" }
      ]
    }
  ],
  "actions": [
    { "id": "local_action", "title": "Machine-local action" }
  ],
  "docs": [
    { "id": "local_doc", "title": "Machine-local doc", "path": "~/Documents/local.md" }
  ]
}
JSON

BARISTA_CONFIG_DIR="$ROOT_DIR" BARISTA_WORKFLOW_EXTRAS="$LOCAL_WORKFLOW" \
  lua "$ROOT_DIR/helpers/generate_shortcuts.lua" \
  "$TMP_DIR/barista_shortcuts.local.conf" "$LOCAL_OUTPUT" >/dev/null

jq -e '.generated.supplement == "BARISTA_WORKFLOW_EXTRAS"' "$LOCAL_OUTPUT" >/dev/null
jq -e '[.keymap[].section] | index("Local Tools") != null' "$LOCAL_OUTPUT" >/dev/null
jq -e '.actions[] | select(.id == "local_action")' "$LOCAL_OUTPUT" >/dev/null
jq -e '.docs[] | select(.id == "local_doc")' "$LOCAL_OUTPUT" >/dev/null

BARISTA_CONFIG_DIR="$ROOT_DIR" lua "$ROOT_DIR/helpers/generate_shortcuts.lua" \
  "$TMP_DIR/barista_shortcuts.second.conf" "$SECOND_OUTPUT" >/dev/null
cmp -s "$WORKFLOW_OUTPUT" "$SECOND_OUTPUT" || {
  echo "FAIL: workflow generation is not deterministic" >&2
  exit 1
}

cmp -s "$WORKFLOW_OUTPUT" "$ROOT_DIR/data/workflow_shortcuts.json" || {
  echo "FAIL: data/workflow_shortcuts.json is stale; run helpers/generate_shortcuts.lua" >&2
  exit 1
}

if grep -Eq '/Users/[^/]+' "$ROOT_DIR/data/workflow_shortcuts.json"; then
  echo "FAIL: generated workflow data contains a machine-specific home path" >&2
  exit 1
fi

printf 'test_generate_shortcuts.sh: ok\n'
