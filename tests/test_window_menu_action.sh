#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/config with spaces" "$TMP_DIR/scripts"
export BARISTA_TEST_ACTION_LOG="$TMP_DIR/action.log"
export BARISTA_TEST_FEEDBACK_LOG="$TMP_DIR/feedback.log"
export BARISTA_TEST_REFRESH_LOG="$TMP_DIR/refresh.log"
export BARISTA_CONFIG_DIR="$TMP_DIR/config with spaces"
export BARISTA_SCRIPTS_DIR="$TMP_DIR/scripts"
export BARISTA_SKETCHYBAR_BIN="$TMP_DIR/sketchybar"
export BARISTA_YABAI_CONTROL_SCRIPT="$TMP_DIR/backend"
export BARISTA_FRONT_APP_ACTION_SCRIPT="$TMP_DIR/app-action"
export BARISTA_FRONT_APP_PLUGIN_SCRIPT="$TMP_DIR/refresh"
export BARISTA_OSASCRIPT_BIN="$TMP_DIR/osascript"

cat > "$TMP_DIR/sketchybar" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >> "$BARISTA_TEST_FEEDBACK_LOG"
STUB
cat > "$TMP_DIR/backend" <<'STUB'
#!/bin/bash
{
  printf 'window=%s\napp=%s\n' "${BARISTA_TARGET_WINDOW_ID:-}" "${BARISTA_TARGET_APP:-}"
  printf 'arg=%s\n' "$@"
} >> "$BARISTA_TEST_ACTION_LOG"
if [ "${BARISTA_TEST_BACKEND_FAIL:-0}" = 1 ]; then
  printf 'Target window no longer exists. Reopen the menu.\n' >&2
  exit 1
fi
STUB
cat > "$TMP_DIR/app-action" <<'STUB'
#!/bin/bash
printf 'arg=%s\n' "$@" >> "$BARISTA_TEST_ACTION_LOG"
STUB
cat > "$TMP_DIR/refresh" <<'STUB'
#!/bin/bash
printf 'app=%s\nsender=%s\n' "$BARISTA_FRONT_APP_TARGET_APP" "$SENDER" >> "$BARISTA_TEST_REFRESH_LOG"
STUB
cat > "$TMP_DIR/osascript" <<'STUB'
#!/bin/bash
printf 'arg=%s\n' "$@" >> "$BARISTA_TEST_ACTION_LOG"
cat > "${BARISTA_TEST_ACTION_LOG}.source"
STUB
chmod +x "$TMP_DIR/sketchybar" "$TMP_DIR/backend" "$TMP_DIR/app-action" "$TMP_DIR/refresh" "$TMP_DIR/osascript"

run_action() {
  : > "$BARISTA_TEST_ACTION_LOG"
  : > "$BARISTA_TEST_FEEDBACK_LOG"
  : > "$BARISTA_TEST_REFRESH_LOG"
  "$ROOT_DIR/scripts/window_menu_action.sh" "$@"
}
assert_line() {
  grep -Fxq -- "$2" "$1" || { printf 'FAIL: missing %s in %s\n' "$2" "$1" >&2; cat "$1" >&2; exit 1; }
}

app_name=$'O\x27Reilly "日本" 🌟'
run_action window window-toggle-float 731 "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'window=731'
assert_line "$BARISTA_TEST_ACTION_LOG" "app=$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=window-toggle-float'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'popup.drawing=on'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Window updated'
assert_line "$BARISTA_TEST_REFRESH_LOG" "app=$app_name"
assert_line "$BARISTA_TEST_REFRESH_LOG" 'sender=action_refresh'

# Stale-window errors remain visible. No refresh can silently replace the target.
if BARISTA_TEST_BACKEND_FAIL=1 run_action window window-toggle-float 731 "$app_name" 2> "$TMP_DIR/error"; then
  echo 'FAIL: stale window action succeeded' >&2; exit 1
fi
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Target window no longer exists. Reopen the menu.'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'popup.drawing=on'
[ ! -s "$BARISTA_TEST_REFRESH_LOG" ]
if run_action window window-toggle-float '' "$app_name" 2> "$TMP_DIR/error"; then
  echo 'FAIL: action without captured window succeeded' >&2; exit 1
fi
[ ! -s "$BARISTA_TEST_ACTION_LOG" ]
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Window unavailable. Reopen the menu.'

run_action default float '' "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=app-default'
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=set'
assert_line "$BARISTA_TEST_ACTION_LOG" "arg=$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=float'
assert_line "$BARISTA_TEST_ACTION_LOG" 'window='
assert_line "$BARISTA_TEST_REFRESH_LOG" "app=$app_name"
run_action default unset 731 "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=unset'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Barista default removed · Other rules may apply'
assert_line "$BARISTA_TEST_ACTION_LOG" 'window='
run_action level raised '' "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=app-level'
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=set'
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=raised'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" "label=$app_name stays above normal windows"
run_action level unset 731 "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=app-level'
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=unset'
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Barista level removed · Yabai rules apply'
if run_action level sideways 731 "$app_name" 2> "$TMP_DIR/error"; then
  echo 'FAIL: unknown level succeeded' >&2; exit 1
fi
assert_line "$BARISTA_TEST_FEEDBACK_LOG" 'label=Unknown app level.'
run_action app hide 731 "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=hide'
assert_line "$BARISTA_TEST_ACTION_LOG" "arg=$app_name"

# AppleScript must receive quoted/unicode app names as argv data, never source.
: > "$BARISTA_TEST_ACTION_LOG"
"$ROOT_DIR/scripts/front_app_action.sh" hide "$app_name"
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=-'
assert_line "$BARISTA_TEST_ACTION_LOG" 'arg=hide'
assert_line "$BARISTA_TEST_ACTION_LOG" "arg=$app_name"
if grep -Fq -- "$app_name" "${BARISTA_TEST_ACTION_LOG}.source"; then
  echo 'FAIL: app name was interpolated into AppleScript' >&2; exit 1
fi

# Force quit targets the app's pid, not a process whose name happens to match.
python3 -c 'import pathlib, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
pathlib.Path(sys.argv[1]).touch()
time.sleep(30)' "$TMP_DIR/victim.ready" &
victim=$!
disown "$victim"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$TMP_DIR/victim.ready" ] && break; sleep 0.1; done
cat > "$TMP_DIR/yabai" <<STUB
#!/bin/bash
printf '[{"app":"Visual Studio Code","pid":$victim}]\n'
STUB
chmod +x "$TMP_DIR/yabai"
BARISTA_YABAI_BIN="$TMP_DIR/yabai" BARISTA_JQ_BIN="$(command -v jq)" \
  "$ROOT_DIR/scripts/front_app_action.sh" force-quit "Visual Studio Code"
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$victim" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$victim" 2>/dev/null; then
  kill -9 "$victim"; echo 'FAIL: force quit left a SIGTERM-ignoring app running' >&2; exit 1
fi
printf 'test_window_menu_action.sh: ok\n'
