#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cat > "$TMP_DIR/yabai" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  '-m query --windows --window 42') printf '{"id":42,"app":"Preview","space":1,"display":1,"layer":"%s","sub-layer":"normal"}\n' "${TEST_APP_LAYER:-normal}"; exit 0 ;;
  '-m query --spaces --display 1') printf '[{"index":1},{"index":2},{"index":3}]\n'; exit 0 ;;
  *'--focus next') exit 1 ;;
  *) exit "${TEST_MUTATION_FAIL:-0}" ;;
esac
STUB
chmod +x "$TMP_DIR/yabai"
export YABAI_BIN="$TMP_DIR/yabai" JQ_BIN="$(command -v jq)" TEST_CALLS="$TMP_DIR/calls"
export BARISTA_FRONT_APP_SCRIPT="$TMP_DIR/no-app" BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/no-runtime" SKETCHYBAR_BIN=/usr/bin/true
run_control() { "$ROOT_DIR/scripts/yabai_control.sh" "$@"; }
for action in window-close window-insert-east window-insert-south window-swap-recent window-toggle-pip; do
  BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview run_control "$action"
done
for command in '--close' '--insert east' '--insert south' '--swap recent' '--toggle pip'; do
  grep -Fxq -- "-m window 42 $command" "$TEST_CALLS"
done
# The window menu runs this under macOS /bin/bash 3.2.
for direction in prev:3 next:2; do
  BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_SPACE_INDEX=1 BARISTA_WINDOW_MOVE_POLICY=preserve \
    /bin/bash "$ROOT_DIR/scripts/yabai_control.sh" "window-space-${direction%%:*}-wrap"
  grep -Fxq -- "-m window 42 --space ${direction#*:}" "$TEST_CALLS"
done
printf '{"window_levels":{"Preview":{"level":"top"}}}\n' > "$TMP_DIR/state.json"
BARISTA_CONFIG_DIR="$TMP_DIR" BARISTA_STATE_FILE="$TMP_DIR/state.json" run_control wm-mode optional >/dev/null
jq -e '.modes.window_manager == "optional" and .window_levels.Preview.level == "top"' "$TMP_DIR/state.json" >/dev/null
printf '{"window_levels":' > "$TMP_DIR/state.json"
if BARISTA_CONFIG_DIR="$TMP_DIR" BARISTA_STATE_FILE="$TMP_DIR/state.json" run_control wm-mode required 2>/dev/null; then
  echo 'FAIL: wm-mode overwrote a corrupt state file' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/state.json")" == '{"window_levels":' ]]
run_control window-focus-next-wrap
grep -Fxq -- '-m window --focus next' "$TEST_CALLS"
grep -Fxq -- '-m window --focus first' "$TEST_CALLS"
if TEST_MUTATION_FAIL=1 run_control window-focus-next-wrap; then echo 'FAIL: focus failure hidden' >&2; exit 1; fi
if TEST_MUTATION_FAIL=1 run_control window-close; then echo 'FAIL: close failure hidden' >&2; exit 1; fi
# App-owned elevation survives a successful sub-layer command. Never report success.
if TEST_APP_LAYER=above BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview run_control window-toggle-topmost > "$TMP_DIR/error" 2>&1; then
  echo 'FAIL: app-owned pin was reported as cleared' >&2; exit 1
fi
grep -Fq 'This app is keeping its window on top' "$TMP_DIR/error"
grep -Fxq -- '-m window 42 --sub-layer below' "$TEST_CALLS"
# A successful command that leaves the window unchanged is also a failure.
if BARISTA_TARGET_WINDOW_ID=42 BARISTA_TARGET_APP=Preview run_control window-toggle-topmost > "$TMP_DIR/error" 2>&1; then
  echo 'FAIL: unchanged topmost state was reported as enabled' >&2; exit 1
fi
grep -Fq 'Always on top did not turn on' "$TMP_DIR/error"
printf 'test_yabai_control_actions.sh: ok\n'

