#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/folio/tasks"
cat > "$TMP_DIR/folio/tasks/active.md" <<'EOF'
# Active Tasks

## Active
- [ ] First active task
- [ ] [NEXT] Explicit next task
- [x] Completed task

## Waiting
- [ ] Waiting task
EOF

BARISTA_CODE_DIR="$TMP_DIR" BARISTA_TEST_ROOT="$ROOT_DIR" lua - <<'LUA'
local root = assert(os.getenv("BARISTA_TEST_ROOT"))
package.path = package.path
  .. ";" .. root .. "/modules/?.lua"
  .. ";" .. root .. "/modules/integrations/?.lua"
  .. ";" .. root .. "/helpers/?.lua"
  .. ";" .. root .. "/?.lua"

local emacs = require("integrations.emacs")
assert(emacs.get_task_count() == 3, "expected three open Markdown tasks")
assert(emacs.get_done_count() == 1, "expected one completed Markdown task")

local tasks = emacs.get_tasks(10)
assert(#tasks == 4, "expected all four task rows")
assert(tasks[1].status == "ACTIVE", "Active section should infer ACTIVE")
assert(tasks[2].status == "NEXT", "explicit state should win")
assert(tasks[3].status == "DONE", "checked task should be DONE")
assert(tasks[4].status == "WAITING", "Waiting section should infer WAITING")
LUA

printf 'test_emacs_tasks.sh: ok\n'
