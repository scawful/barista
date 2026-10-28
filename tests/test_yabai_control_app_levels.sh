#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/yabai_control.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export TEST_DIR="$TMP_DIR"
export BARISTA_STATE_FILE="$TMP_DIR/state.json"
export BARISTA_CONFIG_DIR="$TMP_DIR/config"
export BARISTA_FRONT_APP_CONTEXT_SCRIPT="$TMP_DIR/no-context"
export BARISTA_FRONT_APP_SCRIPT="$TMP_DIR/no-front-app"
export BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/no-runtime"
export SKETCHYBAR_BIN=/usr/bin/true
export JQ_BIN="$(command -v jq)"
export YABAI_BIN="$TMP_DIR/yabai"
printf '{"unrelated":true}\n' > "$BARISTA_STATE_FILE"
# The yabairc base, then a specific rule that later rules can override.
printf '%s\n' '[{"label":"barista-level-base","app":".*","sub-layer":"below"},
  {"label":"","app":"^System Settings$","manage":false,"sub-layer":"normal"}]' > "$TMP_DIR/rules.json"
cat > "$YABAI_BIN" <<'PY'
#!/usr/bin/python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['TEST_DIR'])
args = sys.argv[1:]
with (root/'calls').open('a') as out: out.write(' '.join(args)+'\n')
rules_path = root/'rules.json'
rules = json.loads(rules_path.read_text())
failure = os.environ.get('TEST_FAILURE', '')
windows = [
    {'id': 42, 'app': 'Cursor', 'subrole': 'AXStandardWindow', 'space': 3},
    {'id': 43, 'app': 'Cursor', 'subrole': 'AXStandardWindow', 'space': 8},
    {'id': 44, 'app': 'Cursor', 'subrole': 'AXDialog', 'space': 3},
    {'id': 50, 'app': 'System Settings', 'subrole': 'AXStandardWindow', 'space': 3},
    {'id': 60, 'app': 'Claude', 'subrole': 'AXStandardWindow', 'space': 3},
]
if args == ['-m','rule','--list']:
    print(json.dumps(rules)); sys.exit(0)
if args[:3] == ['-m','rule','--add']:
    if failure == 'install': sys.exit(1)
    if failure != 'verify':
        props = dict(arg.split('=',1) for arg in args[3:])
        rules = [r for r in rules if r['label'] != props['label']]
        rules.append(props)
        rules_path.write_text(json.dumps(rules))
    sys.exit(0)
if args[:3] == ['-m','rule','--remove']:
    rules_path.write_text(json.dumps([r for r in rules if r['label'] != args[3]])); sys.exit(0)
if args == ['-m','query','--windows']:
    print(json.dumps(windows)); sys.exit(0)
pinned = root/'pinned'
if args[:4] == ['-m','query','--windows','--window']:
    print(json.dumps(dict(windows[0], **({'sub-layer': 'above'} if pinned.exists() else {})))); sys.exit(0)
if args[:2] == ['-m','window'] and args[3] == '--sub-layer':
    if args[4] != 'above': pinned.unlink(missing_ok=True)
    sys.exit(0)
sys.exit(1)
PY
chmod +x "$YABAI_BIN"
run_control() { "$SCRIPT" "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; }
expect_failure() {
  if run_control "$@"; then echo "FAIL: expected failure: $*" >&2; exit 1; fi
}
fail() { echo "FAIL: $*" >&2; exit 1; }

# Raising an app installs a level rule after the others, saves it, and moves
# its open standard windows; dialogs and other apps are left alone.
run_control app-level set Cursor raised
"$JQ_BIN" -e '.unrelated and .window_levels.Cursor.level == "raised"
  and .window_levels.Cursor.rule_label == "barista-level-cursor"' "$BARISTA_STATE_FILE" >/dev/null
"$JQ_BIN" -e 'last | .label == "barista-level-cursor" and .["sub-layer"] == "normal" and (has("manage") | not)' \
  "$TMP_DIR/rules.json" >/dev/null
grep -Fxq -- '-m window 42 --sub-layer normal' "$TMP_DIR/calls"
grep -Fxq -- '-m window 43 --sub-layer normal' "$TMP_DIR/calls"
if grep -Eq -- '-m window (44|50|60) ' "$TMP_DIR/calls"; then fail 'moved a window that is not a Cursor document'; fi

run_control app-level set Cursor top
"$JQ_BIN" -e '[.[] | select(.label == "barista-level-cursor")] | length == 1 and .[0]["sub-layer"] == "above"' \
  "$TMP_DIR/rules.json" >/dev/null

# Lowering a utility below its yabairc rule needs an explicit Normal.
: > "$TMP_DIR/calls"
run_control app-level set System Settings normal
grep -Fxq -- '-m window 50 --sub-layer below' "$TMP_DIR/calls"

# Unsetting hands the app back to the remaining rules: the base for Cursor,
# System Settings' own rule for it.
: > "$TMP_DIR/calls"
run_control app-level unset Cursor
"$JQ_BIN" -e '.window_levels.Cursor == null' "$BARISTA_STATE_FILE" >/dev/null
grep -Fxq -- '-m window 42 --sub-layer below' "$TMP_DIR/calls"
grep -Fq 'Yabai rules give it below' "$TMP_DIR/out"
run_control app-level unset System Settings
grep -Fq 'Yabai rules give it normal' "$TMP_DIR/out"

# The focused (or menu-bound) window's app.
run_control app-level-current top
"$JQ_BIN" -e '.window_levels.Cursor.level == "top"' "$BARISTA_STATE_FILE" >/dev/null
run_control app-level list
grep -Fxq 'Cursor: top' "$TMP_DIR/out"

# Nothing is saved unless the rule is verified live.
cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=install expect_failure app-level set Claude raised
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=verify expect_failure app-level set Claude raised
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
expect_failure app-level set Claude sideways
grep -Fq 'Usage:' "$TMP_DIR/err"

# Unpinning a window returns it to its app's level, else the shared base.
run_control app-level set Cursor raised
touch "$TMP_DIR/pinned"; : > "$TMP_DIR/calls"
run_control window-toggle-topmost
grep -Fxq -- '-m window 42 --sub-layer normal' "$TMP_DIR/calls" || fail 'unpinned Raised window left its level'
run_control app-level unset Cursor
touch "$TMP_DIR/pinned"; : > "$TMP_DIR/calls"
run_control window-toggle-topmost
grep -Fxq -- '-m window 42 --sub-layer below' "$TMP_DIR/calls" || fail 'unpinned window should rejoin the base layer'

printf 'test_yabai_control_app_levels.sh: ok\n'
