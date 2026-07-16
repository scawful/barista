#!/bin/bash

set -euo pipefail

if ! command -v lua >/dev/null 2>&1; then
  printf 'test_state_migration.sh: skipped (lua unavailable)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

load_case() {
  local name="$1"
  local case_dir="$TMP_DIR/$name"
  mkdir -p "$case_dir"
  cat > "$case_dir/state.json"
  BARISTA_CONFIG_DIR="$case_dir" BARISTA_TEST_ROOT="$ROOT_DIR" lua -e '
    local root = os.getenv("BARISTA_TEST_ROOT")
    package.path = root .. "/modules/?.lua;" .. root .. "/helpers/lib/?.lua;" .. package.path
    require("state").load()
  '
}

legacy_sources='["~/src/folio/tasks/active.md","~/src/hobby/oracle-of-secrets/Docs/oracle.org"]'

load_case legacy_work <<JSON
{"_version":1,"profile":"work","menus":{"calendar":{"task_sources":$legacy_sources}},"widgets":{}}
JSON
jq -e '
  ._version == 2 and
  .profile == "work" and
  .menus.calendar.task_provider == "files" and
  .menus.calendar.task_sources == [] and
  .menus.calendar.meeting_cache_file == "" and
  .widgets.task_focus == false
' "$TMP_DIR/legacy_work/state.json" >/dev/null

load_case custom_work <<'JSON'
{"_version":1,"profile":"work","menus":{"calendar":{"task_sources":["~/work/tasks.md"]}},"widgets":{}}
JSON
jq -e '._version == 2 and .menus.calendar.task_sources == ["~/work/tasks.md"]' \
  "$TMP_DIR/custom_work/state.json" >/dev/null

load_case personal_legacy <<JSON
{"_version":1,"profile":"personal","menus":{"calendar":{"task_sources":$legacy_sources}},"widgets":{}}
JSON
jq -e --argjson legacy "$legacy_sources" \
  '._version == 2 and .menus.calendar.task_sources == $legacy' \
  "$TMP_DIR/personal_legacy/state.json" >/dev/null

load_case implicit_minimal_legacy <<JSON
{"_version":1,"menus":{"calendar":{"task_sources":$legacy_sources}},"widgets":{}}
JSON
jq -e '
  ._version == 2 and
  (.profile == null) and
  .menus.calendar.task_sources == [] and
  .widgets.task_focus == false
' "$TMP_DIR/implicit_minimal_legacy/state.json" >/dev/null

load_case explicit_work_opt_in <<JSON
{"_version":1,"profile":"work","menus":{"calendar":{"task_provider":"syshelp","task_sources":$legacy_sources}},"widgets":{"task_focus":true}}
JSON
jq -e --argjson legacy "$legacy_sources" '
  ._version == 2 and
  .menus.calendar.task_provider == "syshelp" and
  .menus.calendar.task_sources == $legacy and
  .widgets.task_focus == true
' "$TMP_DIR/explicit_work_opt_in/state.json" >/dev/null

printf 'test_state_migration.sh: ok\n'
