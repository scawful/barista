#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/restricted_config.py"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

STATE_FILE="$TMP_DIR/state.json"

python3 "$SCRIPT" apply \
  --state "$STATE_FILE" \
  --domain example.com \
  --work-apps-out-file data/work_apps.local.json \
  --replace \
  --report \
  --no-reload >"$TMP_DIR/apply.report"

python3 - "$STATE_FILE" "$TMP_DIR/work_apps" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
state = json.loads(state_path.read_text())
assert state["profile"] == "work"
assert state["modes"]["window_manager"] == "disabled"
assert state["modes"]["runtime_backend"] == "lua"
assert state["modes"]["widget_daemon"] == "disabled"
assert state["control_panel"]["preferred"] == "tui"
assert state["toggles"]["yabai_shortcuts"] is False
assert state["menus"]["work"]["workspace_domain"] == "example.com"

apps_file = state_path.parent / state["menus"]["work"]["apps_file"]
apps = json.loads(apps_file.read_text())
assert len(apps) == 6
assert apps[0]["id"] == "work_google_gmail"
assert apps[0]["url"] == "https://mail.google.com/a/example.com/"
PY

python3 "$SCRIPT" menu-item \
  --state "$STATE_FILE" \
  --id runbook \
  --label "Runbook" \
  --url "https://example.com/runbook" \
  --section work \
  --order 10 \
  --no-reload

python3 - "$STATE_FILE" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
custom = state["menus"]["apple"]["custom"]
runbook = [item for item in custom if item.get("id") == "runbook"]
assert len(runbook) == 1
assert runbook[0]["url"] == "https://example.com/runbook"
PY

"$ROOT_DIR/scripts/configure_work_google_apps.sh" \
  --state "$STATE_FILE" \
  --domain corp.example \
  --work-apps-out-file data/work_apps.local.json \
  --replace \
  --report \
  --no-reload >"$TMP_DIR/work.report"

python3 - "$STATE_FILE" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
state = json.loads(state_path.read_text())
apps = json.loads((state_path.parent / state["menus"]["work"]["apps_file"]).read_text())
assert state["menus"]["work"]["workspace_domain"] == "corp.example"
assert apps[1]["url"] == "https://calendar.google.com/a/corp.example/"
PY

printf 'test_restricted_config.sh: ok\n'
