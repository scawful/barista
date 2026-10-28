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
printf '{"unrelated":{"theme":"cozy"},"window_defaults":{"apps":[]}}\n' > "$BARISTA_STATE_FILE"
printf '[]\n' > "$TMP_DIR/rules.json"
printf 'false\n' > "$TMP_DIR/floating"
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
if args == ['-m','rule','--list']:
    print(json.dumps(rules)); sys.exit(0)
if args[:3] == ['-m','rule','--add']:
    if failure == 'install': sys.exit(1)
    if failure != 'verify':
        props = dict(arg.split('=',1) for arg in args[3:])
        props['manage'] = props['manage'] == 'on'
        rules = [r for r in rules if r['label'] != props['label']]
        rules.append(props)
        rules_path.write_text(json.dumps(rules))
    if failure == 'persist': Path(os.environ['BARISTA_STATE_FILE']).write_text('broken')
    sys.exit(0)
if args[:3] == ['-m','rule','--remove']:
    if failure == 'remove': sys.exit(1)
    rules_path.write_text(json.dumps([r for r in rules if r['label'] != args[3]])); sys.exit(0)
if args[:4] == ['-m','query','--windows','--window']:
    if len(args) == 5 and (args[4] != '42' or failure == 'gone'): sys.exit(1)
    # The first focus query identifies Preview; a later one points to Other.
    if len(args) == 4:
        marker = root/'focus-queried'
        app = 'Other' if marker.exists() else 'Preview'
        marker.touch()
    else: app = 'Preview'
    print(json.dumps({'id':42 if app == 'Preview' else 77,'app':app,'space':1,'display':1,
        'is-floating':(root/'floating').read_text().strip() == 'true'})); sys.exit(0)
if args[:4] == ['-m','query','--spaces','--space']:
    print('{"index":1,"id":101,"display":1,"type":"bsp"}'); sys.exit(0)
if args[:4] == ['-m','window','42','--toggle']:
    if failure == 'window': sys.exit(1)
    if args[4] == 'float':
        (root/'floating').write_text('false' if (root/'floating').read_text().strip() == 'true' else 'true')
    sys.exit(0)
if args[:3] == ['-m','window','42']: sys.exit(1 if failure == 'window' else 0)
sys.exit(1)
PY
chmod +x "$YABAI_BIN"
run_control() { "$SCRIPT" "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; }
expect_failure() {
  if run_control "$@"; then echo "FAIL: expected failure: $*" >&2; exit 1; fi
}

run_control app-default set Logic Pro float
"$JQ_BIN" -e '.unrelated.theme == "cozy" and .window_defaults.apps["Logic Pro"].manage == "off"' "$BARISTA_STATE_FILE" >/dev/null
# Floating never pins stacking; that is the app level's job.
"$JQ_BIN" -e 'all(.[]; has("sub-layer") | not)' "$TMP_DIR/rules.json" >/dev/null
run_control app-default set Logic Pro tile
"$JQ_BIN" -e '.window_defaults.apps["Logic Pro"].mode == "tile"' "$BARISTA_STATE_FILE" >/dev/null
cp "$TMP_DIR/rules.json" "$TMP_DIR/rules-before"
TEST_FAILURE=install expect_failure app-default set Logic Pro float
cmp "$TMP_DIR/rules.json" "$TMP_DIR/rules-before"
run_control app-default unset Logic Pro
"$JQ_BIN" -e '.window_defaults.apps == {}' "$BARISTA_STATE_FILE" >/dev/null
grep -Fq 'other Yabai rules still apply' "$TMP_DIR/out"

cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=install expect_failure app-default set Preview float
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=verify expect_failure app-default set Preview float
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
run_control app-default-current float
"$JQ_BIN" -e '.window_defaults.apps.Preview.mode == "float" and .window_defaults.apps.Other == null' "$BARISTA_STATE_FILE" >/dev/null
grep -Fxq -- '-m window 42 --toggle float' "$TMP_DIR/calls"
[ "$(grep -Fc -- '-m query --windows --window' "$TMP_DIR/calls")" -ge 1 ]
if grep -Fq -- '-m window 77' "$TMP_DIR/calls"; then echo 'FAIL: action followed focus' >&2; exit 1; fi

cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=remove expect_failure app-default unset Preview
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"

: > "$TMP_DIR/calls"
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview run_control window-toggle-sticky
grep -Fxq -- '-m window 42 --toggle sticky' "$TMP_DIR/calls"
: > "$TMP_DIR/calls"
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Other expect_failure window-toggle-float
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview TEST_FAILURE=gone expect_failure window-center
if grep -Fq -- '-m window ' "$TMP_DIR/calls"; then echo 'FAIL: stale target mutated a window' >&2; exit 1; fi

printf 'false' > "$TMP_DIR/floating"
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview TEST_FAILURE=window expect_failure window-preset-utility
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview TEST_FAILURE=window expect_failure window-preset-presentation
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview TEST_FAILURE=window expect_failure window-toggle-topmost
printf 'true' > "$TMP_DIR/floating"
BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview TEST_FAILURE=window expect_failure window-adopt-space-mode

printf 'broken' > "$BARISTA_STATE_FILE"
cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
: > "$TMP_DIR/calls"
expect_failure app-default set Preview tile
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
if grep -Fq -- '-m rule --add' "$TMP_DIR/calls"; then echo 'FAIL: mutated rule with invalid state' >&2; exit 1; fi

printf '{"window_defaults":{"apps":[1]},"unrelated":true}' > "$BARISTA_STATE_FILE"
cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
expect_failure app-default set Preview tile
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"

printf '{}' > "$BARISTA_STATE_FILE"
TEST_FAILURE=persist expect_failure app-default set Preview float
grep -Fq 'could not be saved' "$TMP_DIR/err"
printf 'test_yabai_control_app_defaults.sh: ok\n'
