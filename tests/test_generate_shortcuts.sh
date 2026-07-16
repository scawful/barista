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
jq -e '.keymap[0].items[] | select(.action == "capture_task" and .keys == "⌘⌥N")' \
  "$WORKFLOW_OUTPUT" >/dev/null
jq -e '.keymap[0].items[] | select(.action == "capture_task" and .requires == "task_source")' \
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

RUNTIME_CONFIG="$TMP_DIR/runtime-config"
RUNTIME_SKHD="$TMP_DIR/runtime-shortcuts.conf"
RUNTIME_WORKFLOW="$TMP_DIR/runtime-workflow.json"
TASK_LOG="$TMP_DIR/task-action.log"
mkdir -p "$RUNTIME_CONFIG/helpers" "$RUNTIME_CONFIG/scripts"
ln -s "$ROOT_DIR/modules" "$RUNTIME_CONFIG/modules"
ln -s "$ROOT_DIR/helpers/lib" "$RUNTIME_CONFIG/helpers/lib"
cat >"$RUNTIME_CONFIG/state.json" <<'JSON'
{
  "menus": {
    "calendar": {
      "task_provider": "files",
      "task_sources": []
    }
  }
}
JSON
cat >"$RUNTIME_CONFIG/barista_config.lua" <<'LUA'
return {
  menus = {
    calendar = {
      task_sources = { "~/tasks/config's board.md" },
      capture_section = "Configured",
    },
  },
}
LUA
cat >"$RUNTIME_CONFIG/scripts/task_capture.sh" <<'SH'
#!/bin/sh
printf '%s\n%s\n%s\n' \
  "${BARISTA_CALENDAR_TASK_SOURCES:-}" \
  "${BARISTA_TASK_PROVIDER:-}" \
  "${BARISTA_CAPTURE_SECTION:-}" >"${BARISTA_SHORTCUT_TEST_LOG:?}"
SH
chmod +x "$RUNTIME_CONFIG/scripts/task_capture.sh"

BARISTA_CONFIG_DIR="$RUNTIME_CONFIG" lua "$ROOT_DIR/helpers/generate_shortcuts.lua" \
  "$RUNTIME_SKHD" "$RUNTIME_WORKFLOW" >/dev/null
grep -Fq '# barista-action: capture_task' "$RUNTIME_SKHD"
runtime_command="$(sed -n 's/^cmd + alt - n : //p' "$RUNTIME_SKHD")"
[ -n "$runtime_command" ] || {
  echo "FAIL: barista_config.lua task source did not enable capture" >&2
  exit 1
}
export BARISTA_SHORTCUT_TEST_LOG="$TASK_LOG"
eval "$runtime_command"
# Task sources intentionally preserve a literal tilde.
# shellcheck disable=SC2088
EXPECTED_CONFIG_SOURCE="~/tasks/config's board.md"
[ "$(sed -n '1p' "$TASK_LOG")" = "$EXPECTED_CONFIG_SOURCE" ]
[ "$(sed -n '2p' "$TASK_LOG")" = "files" ]
[ "$(sed -n '3p' "$TASK_LOG")" = "Configured" ]

SUBSTITUTION_MARKER="$TMP_DIR/substitution-ran"
BACKTICK_MARKER="$TMP_DIR/backtick-ran"
HOSTILE_SOURCE="\$(touch '$SUBSTITUTION_MARKER') and \`touch '$BACKTICK_MARKER'\` and it's data"
BARISTA_CONFIG_DIR="$RUNTIME_CONFIG" \
  BARISTA_CALENDAR_TASK_SOURCES="   " \
  BARISTA_TASK_SOURCES="$HOSTILE_SOURCE" \
  BARISTA_TASK_PROVIDER="syshelp" \
  lua "$ROOT_DIR/helpers/generate_shortcuts.lua" \
    "$RUNTIME_SKHD" "$RUNTIME_WORKFLOW" >/dev/null
runtime_command="$(sed -n 's/^cmd + alt - n : //p' "$RUNTIME_SKHD")"
eval "$runtime_command"
[ "$(sed -n '1p' "$TASK_LOG")" = "$HOSTILE_SOURCE" ]
[ "$(sed -n '2p' "$TASK_LOG")" = "syshelp" ]
if [ -e "$SUBSTITUTION_MARKER" ] || [ -e "$BACKTICK_MARKER" ]; then
  echo "FAIL: generated task shortcut executed shell substitutions from configuration" >&2
  exit 1
fi

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
