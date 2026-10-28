#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/set_space_mode.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export TEST_DIR="$TMP_DIR"
export BARISTA_STATE_FILE="$TMP_DIR/state.json"
export BARISTA_CONFIG_DIR="$TMP_DIR/config"
export SKETCHYBAR_BIN=/usr/bin/true
export JQ_BIN="$(command -v jq)"
export YABAI_BIN="$TMP_DIR/yabai"
export BARISTA_FRONT_APP_SCRIPT="$TMP_DIR/no-front-app"
export BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/no-runtime"
printf '{"unrelated":{"theme":"cozy"},"space_modes":{"1":"bsp"}}\n' > "$BARISTA_STATE_FILE"
printf 'bsp\n' > "$TMP_DIR/layout"
cat > "$YABAI_BIN" <<'PY'
#!/usr/bin/python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['TEST_DIR'])
args = sys.argv[1:]
with (root/'calls').open('a') as out: out.write(' '.join(args)+'\n')
failure = os.environ.get('TEST_FAILURE', '')
if args[:4] == ['-m','query','--spaces','--space']:
    if len(args) == 5 and args[4] != '2': sys.exit(1)
    ident = 202 if failure != 'identity' or not (root/'applied').exists() else 999
    print(json.dumps({'index':2,'id':ident,'display':1,'type':(root/'layout').read_text().strip(),
        'is-native-fullscreen':failure == 'fullscreen'})); sys.exit(0)
if args[:4] == ['-m','space','2','--layout']:
    if failure == 'apply': sys.exit(1)
    if failure != 'verify': (root/'layout').write_text(args[4])
    if failure == 'persist': Path(os.environ['BARISTA_STATE_FILE']).write_text('broken')
    (root/'applied').touch(); sys.exit(0)
if args[:3] == ['-m','space','2']: sys.exit(0)
sys.exit(1)
PY
chmod +x "$YABAI_BIN"
run_mode() { "$SCRIPT" "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; }
expect_failure() {
  if run_mode "$@"; then echo "FAIL: expected failure: $*" >&2; exit 1; fi
}
run_mode current stack
"$JQ_BIN" -e '.unrelated.theme == "cozy" and .space_modes["1"] == "bsp" and .space_modes["2"] == "stack"' "$BARISTA_STATE_FILE" >/dev/null
grep -Fxq -- '-m space 2 --layout stack' "$TMP_DIR/calls"
run_mode 2 float
"$JQ_BIN" -e '.space_modes["2"] == "float"' "$BARISTA_STATE_FILE" >/dev/null
if grep -Fq -- '--toggle float' "$TMP_DIR/calls"; then echo 'FAIL: float layout must not toggle' >&2; exit 1; fi

cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
: > "$TMP_DIR/calls"
expect_failure 2 nonsense
expect_failure wrong bsp
expect_failure 99 bsp
BARISTA_TARGET_SPACE_ID=999 expect_failure 2 bsp
TEST_FAILURE=fullscreen expect_failure 2 bsp
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
if grep -Fq -- '-m space ' "$TMP_DIR/calls"; then echo 'FAIL: invalid target mutated layout' >&2; exit 1; fi
TEST_FAILURE=apply expect_failure 2 bsp
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
TEST_FAILURE=verify expect_failure 2 stack
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
rm -f "$TMP_DIR/applied"
TEST_FAILURE=identity expect_failure 2 stack
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"

# Control Center operations stay on the shown space after focus changes.
: > "$TMP_DIR/calls"
BARISTA_TARGET_SPACE_INDEX=2 BARISTA_TARGET_SPACE_ID=202 "$ROOT_DIR/scripts/yabai_control.sh" balance > "$TMP_DIR/out"
grep -Fxq -- '-m space 2 --balance' "$TMP_DIR/calls"
if BARISTA_TARGET_SPACE_INDEX=2 BARISTA_TARGET_SPACE_ID=999 "$ROOT_DIR/scripts/yabai_control.sh" space-rotate > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
  echo 'FAIL: stale space accepted' >&2; exit 1
fi
BARISTA_TARGET_SPACE_INDEX=2 BARISTA_TARGET_SPACE_ID=202 "$ROOT_DIR/scripts/yabai_control.sh" toggle-layout > "$TMP_DIR/out"
"$JQ_BIN" -e '.space_modes["2"] == "bsp"' "$BARISTA_STATE_FILE" >/dev/null

printf 'broken' > "$BARISTA_STATE_FILE"
cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
: > "$TMP_DIR/calls"
expect_failure 2 bsp
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
if grep -Fq -- '-m space ' "$TMP_DIR/calls"; then echo 'FAIL: invalid state mutated layout' >&2; exit 1; fi
printf '{"space_modes":[1],"unrelated":true}' > "$BARISTA_STATE_FILE"
cp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
expect_failure 2 bsp
cmp "$BARISTA_STATE_FILE" "$TMP_DIR/before"
printf '{}' > "$BARISTA_STATE_FILE"
TEST_FAILURE=persist expect_failure 2 bsp
grep -Fq 'could not be saved' "$TMP_DIR/err"

# The shared writer serializes independent app and space updates.
printf '{"unrelated":{"theme":"cozy"},"space_modes":[],"window_defaults":{"apps":[]}}' > "$BARISTA_STATE_FILE"
for index in 1 2 3 4 5 6 7 8; do
  python3 "$ROOT_DIR/scripts/yabai_state.py" "$BARISTA_STATE_FILE" space-mode "$index" bsp &
  python3 "$ROOT_DIR/scripts/yabai_state.py" "$BARISTA_STATE_FILE" app-default "App $index" tile "^App $index$" "app-$index" &
done
wait
"$JQ_BIN" -e '.unrelated.theme == "cozy" and (.space_modes | length) == 8 and (.window_defaults.apps | length) == 8' "$BARISTA_STATE_FILE" >/dev/null
printf 'test_set_space_mode.sh: ok\n'
