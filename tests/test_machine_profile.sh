#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/machine_profile.py"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

STATE_FILE="$TMP_DIR/state.json"
MACHINE_FILE="$TMP_DIR/machine.local.json"

python3 "$SCRIPT" apply \
  --variant restricted-work \
  --state "$STATE_FILE" \
  --machine-file "$MACHINE_FILE" \
  --domain example.com \
  --replace \
  --report \
  --no-reload >"$TMP_DIR/restricted.report"

python3 - "$STATE_FILE" "$MACHINE_FILE" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
machine = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert state["profile"] == "work"
assert state["modes"]["window_manager"] == "disabled"
assert state["modes"]["runtime_backend"] == "lua"
assert state["modes"]["widget_daemon"] == "disabled"
assert state["toggles"]["yabai_shortcuts"] is False
assert machine["profile_variant"] == "restricted-work"
assert machine["restricted"] is True
assert machine["allowed_features"]["native_panel"] is False
assert machine["allowed_features"]["compiled_helpers"] is False
assert machine["allowed_features"]["work_apps"] is True
apps = json.loads((pathlib.Path(sys.argv[1]).parent / state["menus"]["work"]["apps_file"]).read_text())
assert apps[0]["url"] == "https://mail.google.com/a/example.com/"
PY

COZY_STATE="$TMP_DIR/cozy-state.json"
COZY_MACHINE="$TMP_DIR/cozy-machine.json"
python3 "$SCRIPT" apply \
  --variant cozy \
  --state "$COZY_STATE" \
  --machine-file "$COZY_MACHINE" \
  --runtime-backend lua \
  --panel-mode tui \
  --report \
  --no-reload >"$TMP_DIR/cozy.report"

python3 - "$COZY_STATE" "$COZY_MACHINE" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
machine = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert state["profile"] == "cozy"
assert state["modes"]["window_manager"] == "disabled"
assert state["modes"]["runtime_backend"] == "lua"
assert state["control_panel"]["preferred"] == "tui"
assert machine["profile_variant"] == "cozy"
assert machine["menu_packs"] == ["core", "restricted_safe"]
assert machine["modes"]["runtime_backend"] == "lua"
PY

python3 "$SCRIPT" capabilities --format env >"$TMP_DIR/capabilities.env"
grep -q '^capability.python3=' "$TMP_DIR/capabilities.env"

"$ROOT_DIR/scripts/setup_machine.sh" \
  --state "$TMP_DIR/setup-state.json" \
  --machine-file "$TMP_DIR/setup-machine.json" \
  --profile-variant cozy \
  --skip-fonts \
  --skip-panel \
  --yes \
  --no-reload \
  --report >"$TMP_DIR/setup.report"

python3 - "$TMP_DIR/setup-state.json" "$TMP_DIR/setup-machine.json" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
machine = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert state["profile"] == "cozy"
assert machine["profile_variant"] == "cozy"
PY

printf 'test_machine_profile.sh: ok\n'
