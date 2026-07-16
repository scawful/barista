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
STATE_SEED="$TMP_DIR/personal-state-seed.json"
export BARISTA_SKHD_SHORTCUTS_FILE="$TMP_DIR/direct-shortcuts.conf"
export BARISTA_RELOAD_SKHD=0

cat >"$BARISTA_SKHD_SHORTCUTS_FILE" <<'SKHD'
# stale direct task bindings
cmd + alt - d : BARISTA_CALENDAR_TASK_SOURCES='~/private/direct-tasks.md' '/tmp/task_focus.sh'
cmd + alt - n : BARISTA_CALENDAR_TASK_SOURCES='~/private/direct-tasks.md' '/tmp/task_capture.sh'
SKHD

cat >"$STATE_SEED" <<'JSON'
{
  "_version": 7,
  "profile": "personal",
  "integrations": {
    "oracle": {"enabled": true, "label": "keep-oracle"},
    "music": {"enabled": true},
    "journal": {"enabled": true},
    "nerv": {"enabled": true},
    "yaze": {"enabled": true},
    "halext": {"enabled": true, "server_url": "http://127.0.0.1:8765"},
    "halext_org": {"enabled": true},
    "workspace": {"enabled": true},
    "unrelated": {"enabled": true, "option": "keep-integration"}
  },
  "menus": {
    "calendar": {
      "task_provider": "halext",
      "task_sources": ["~/private-tasks.md"],
      "meeting_cache_file": "~/.cache/private-calendar/events.tsv",
      "syshelp_path": "/Users/personal/bin/syshelp",
      "custom_option": "keep-calendar"
    },
    "unrelated": {"option": "keep-menu"}
  },
  "widgets": {"task_focus": true, "clock": false},
  "custom_root": {"option": "keep-root"}
}
JSON

cp "$STATE_SEED" "$STATE_FILE"

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
for name in ("oracle", "music", "journal", "nerv", "yaze", "halext", "halext_org", "workspace"):
    assert state["integrations"][name]["enabled"] is False
assert state["integrations"]["oracle"]["label"] == "keep-oracle"
assert state["integrations"]["halext"]["server_url"] == "http://127.0.0.1:8765"
assert state["integrations"]["unrelated"] == {"enabled": True, "option": "keep-integration"}
assert state["menus"]["calendar"]["task_provider"] == "files"
assert state["menus"]["calendar"]["task_sources"] == []
assert state["menus"]["calendar"]["meeting_cache_file"] == ""
assert state["menus"]["calendar"]["syshelp_path"] == ""
assert state["menus"]["calendar"]["custom_option"] == "keep-calendar"
assert state["menus"]["unrelated"] == {"option": "keep-menu"}
assert state["widgets"]["task_focus"] is False
assert state["widgets"]["clock"] is False
assert state["custom_root"] == {"option": "keep-root"}
apps = json.loads((pathlib.Path(sys.argv[1]).parent / state["menus"]["work"]["apps_file"]).read_text())
assert apps[0]["url"] == "https://mail.google.com/a/example.com/"
PY

grep -Fq '# barista-action: open_task_focus' "$BARISTA_SKHD_SHORTCUTS_FILE"
if grep -Fq 'direct-tasks.md' "$BARISTA_SKHD_SHORTCUTS_FILE" \
  || grep -Fq 'cmd + alt - n :' "$BARISTA_SKHD_SHORTCUTS_FILE"; then
  echo "FAIL: direct restricted profile apply left personal task bindings" >&2
  exit 1
fi

WORK_STATE="$TMP_DIR/work-state.json"
WORK_MACHINE="$TMP_DIR/work-machine.json"
cp "$STATE_SEED" "$WORK_STATE"
python3 "$SCRIPT" apply \
  --variant work \
  --state "$WORK_STATE" \
  --machine-file "$WORK_MACHINE" \
  --skip-work-apps \
  --report \
  --no-reload >"$TMP_DIR/work.report"

python3 - "$WORK_STATE" "$WORK_MACHINE" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
machine = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert state["profile"] == "work"
assert machine["profile_variant"] == "work"
assert machine["restricted"] is False
for name in ("oracle", "music", "journal", "nerv", "yaze", "halext", "halext_org", "workspace"):
    assert state["integrations"][name]["enabled"] is False
assert state["integrations"]["oracle"]["label"] == "keep-oracle"
assert state["integrations"]["halext"]["server_url"] == "http://127.0.0.1:8765"
assert state["integrations"]["unrelated"] == {"enabled": True, "option": "keep-integration"}
assert state["menus"]["calendar"]["task_provider"] == "files"
assert state["menus"]["calendar"]["task_sources"] == []
assert state["menus"]["calendar"]["meeting_cache_file"] == ""
assert state["menus"]["calendar"]["syshelp_path"] == ""
assert state["menus"]["calendar"]["custom_option"] == "keep-calendar"
assert state["menus"]["unrelated"] == {"option": "keep-menu"}
assert state["widgets"]["task_focus"] is False
assert state["widgets"]["clock"] is False
assert state["custom_root"] == {"option": "keep-root"}
PY

COZY_STATE="$TMP_DIR/cozy-state.json"
COZY_MACHINE="$TMP_DIR/cozy-machine.json"
cp "$STATE_SEED" "$COZY_STATE"
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
assert state["integrations"]["oracle"]["enabled"] is True
assert state["integrations"]["halext"]["enabled"] is True
assert state["menus"]["calendar"]["task_provider"] == "halext"
assert state["menus"]["calendar"]["task_sources"] == ["~/private-tasks.md"]
assert state["menus"]["calendar"]["meeting_cache_file"] == "~/.cache/private-calendar/events.tsv"
assert state["menus"]["calendar"]["syshelp_path"] == "/Users/personal/bin/syshelp"
assert state["widgets"]["task_focus"] is True
assert state["custom_root"] == {"option": "keep-root"}
PY

for variant in minimal personal; do
  variant_state="$TMP_DIR/$variant-state.json"
  variant_machine="$TMP_DIR/$variant-machine.json"
  cp "$STATE_SEED" "$variant_state"
  python3 "$SCRIPT" apply \
    --variant "$variant" \
    --state "$variant_state" \
    --machine-file "$variant_machine" \
    --skip-work-apps \
    --no-reload

  python3 - "$variant_state" "$variant_machine" "$variant" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
machine = json.loads(pathlib.Path(sys.argv[2]).read_text())
variant = sys.argv[3]
assert state["profile"] == variant
assert machine["profile_variant"] == variant
assert state["integrations"]["oracle"]["enabled"] is True
assert state["integrations"]["halext"]["enabled"] is True
assert state["menus"]["calendar"]["task_provider"] == "halext"
assert state["menus"]["calendar"]["task_sources"] == ["~/private-tasks.md"]
assert state["menus"]["calendar"]["meeting_cache_file"] == "~/.cache/private-calendar/events.tsv"
assert state["menus"]["calendar"]["syshelp_path"] == "/Users/personal/bin/syshelp"
assert state["widgets"]["task_focus"] is True
assert state["custom_root"] == {"option": "keep-root"}
PY
done

python3 "$SCRIPT" capabilities --format env >"$TMP_DIR/capabilities.env"
grep -q '^capability.python3=' "$TMP_DIR/capabilities.env"

HOME="$TMP_DIR/setup-home" \
BARISTA_RELOAD_SKHD=0 \
BARISTA_SKHD_CONFIG_FILE="$TMP_DIR/setup-home/.config/skhd/skhdrc" \
BARISTA_SKHD_SHORTCUTS_FILE="$TMP_DIR/setup-shortcuts.conf" \
BARISTA_RUNTIME_WORKFLOW_FILE="$TMP_DIR/setup-workflow.json" \
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
