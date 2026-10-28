#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/launch_agents/barista-launch.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
HOME_DIR="$TMP_DIR/home"
CONFIG_FIXTURE="$TMP_DIR/runtime with spaces"
BIN_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/actions.log"
PLIST_DIR="$HOME_DIR/Library/LaunchAgents"
mkdir -p "$CONFIG_FIXTURE" "$BIN_DIR" "$PLIST_DIR"

cat > "$BIN_DIR/helper" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$BARISTA_TEST_ACTION_LOG"
if [ "${BARISTA_TEST_FAIL_YABAI:-0}" = 1 ] && [ "${2:-}" = com.example.yabai ]; then exit 1; fi
if [ "${BARISTA_TEST_FAIL_SKHD:-0}" = 1 ] && [ "${2:-}" = com.example.skhd ]; then exit 119; fi
STUB
cat > "$BIN_DIR/launchctl" <<'STUB'
#!/bin/bash
printf 'launchctl %s\n' "$*" >> "$BARISTA_TEST_ACTION_LOG"
case "${1:-}" in
  print) exit "${BARISTA_TEST_LOADED_STATUS:-0}" ;;
  setenv|unsetenv) exit 99 ;;
esac
STUB
cat > "$BIN_DIR/id" <<'STUB'
#!/bin/bash
if [ "${1:-}" = -u ]; then printf '501\n'; else /usr/bin/id "$@"; fi
STUB
chmod +x "$BIN_DIR/helper" "$BIN_DIR/launchctl" "$BIN_DIR/id"
printf 'fixture\n' > "$PLIST_DIR/com.example.yabai.plist"
printf 'fixture\n' > "$PLIST_DIR/com.example.skhd.plist"
printf 'fixture\n' > "$PLIST_DIR/com.example.sketchybar.plist"

run_launcher() {
  : > "$LOG"
  HOME="$HOME_DIR" BARISTA_CONFIG_DIR="$CONFIG_FIXTURE" \
    HOMEBREW_PREFIX=/opt/homebrew \
    BARISTA_PATH="$BIN_DIR:/usr/bin:/bin:/opt/homebrew/bin" \
    BARISTA_AGENT_HELPER="${TEST_HELPER:-$BIN_DIR/helper}" \
    BARISTA_YABAI_LABEL=com.example.yabai \
    BARISTA_SKHD_LABEL=com.example.skhd \
    BARISTA_SKETCHYBAR_LABEL=com.example.sketchybar \
    BARISTA_TEST_ACTION_LOG="$LOG" \
    bash "$SCRIPT" "$@" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"
}
assert_actions() {
  [ "$(cat "$LOG")" = "$1" ] || {
    printf 'FAIL: expected launcher actions:\n%s\nActual:\n' "$1" >&2
    cat "$LOG" >&2
    exit 1
  }
}
write_state() {
  printf '{"modes":{"window_manager":"%s"},"toggles":{"yabai_shortcuts":%s},"custom":{"keep":true}}\n' "$1" "$2" > "$CONFIG_FIXTURE/state.json"
  cp "$CONFIG_FIXTURE/state.json" "$TMP_DIR/state.before"
}
assert_state_unchanged() { cmp "$TMP_DIR/state.before" "$CONFIG_FIXTURE/state.json"; }

write_state auto true
run_launcher start
assert_actions $'start com.example.yabai\nstart com.example.skhd\nstart com.example.sketchybar'
assert_state_unchanged
write_state required false
run_launcher restart
assert_actions $'restart com.example.yabai\nrestart com.example.sketchybar'
assert_state_unchanged
write_state optional true
run_launcher start
assert_actions $'start com.example.skhd\nstart com.example.sketchybar'
write_state disabled true
run_launcher start
assert_actions 'start com.example.sketchybar'
assert_state_unchanged

# Missing optional services do not prevent the bar from starting.
mv "$PLIST_DIR/com.example.yabai.plist" "$TMP_DIR/yabai.plist"
mv "$PLIST_DIR/com.example.skhd.plist" "$TMP_DIR/skhd.plist"
write_state auto true
run_launcher start
assert_actions 'start com.example.sketchybar'
mv "$TMP_DIR/yabai.plist" "$PLIST_DIR/com.example.yabai.plist"
mv "$TMP_DIR/skhd.plist" "$PLIST_DIR/com.example.skhd.plist"

# Invalid preference files fail before any lifecycle action and remain intact.
for invalid in '{broken' '[]' '{"modes":{"window_manager":"typo"}}' '{"toggles":{"yabai_shortcuts":"false"}}'; do
  printf '%s\n' "$invalid" > "$CONFIG_FIXTURE/state.json"
  cp "$CONFIG_FIXTURE/state.json" "$TMP_DIR/state.before"
  if run_launcher start; then echo 'FAIL: invalid state started services' >&2; exit 1; fi
  assert_actions ''
  assert_state_unchanged
  [ -s "$TMP_DIR/stderr" ]
done

# Mode aliases the Lua resolver accepts (set_mode.sh stores them verbatim).
write_state off true
run_launcher start
assert_actions 'start com.example.sketchybar'
write_state Enabled false
run_launcher start
assert_actions $'start com.example.yabai\nstart com.example.sketchybar'

# An optional service that fails to start does not keep the bar down.
write_state auto true
BARISTA_TEST_FAIL_SKHD=1 run_launcher start
assert_actions $'start com.example.yabai\nstart com.example.skhd\nstart com.example.sketchybar'

# Required service failure cannot race ahead into SketchyBar initialization.
write_state required true
if BARISTA_TEST_FAIL_YABAI=1 run_launcher start; then
  echo 'FAIL: required service failure was ignored' >&2; exit 1
fi
assert_actions 'start com.example.yabai'

# Fallback path is equally non-destructive, and never changes global launchd env.
write_state disabled false
TEST_HELPER="$TMP_DIR/missing-helper" run_launcher start
assert_actions $'launchctl print gui/501/com.example.sketchybar\nlaunchctl kickstart -p gui/501/com.example.sketchybar'
TEST_HELPER="$TMP_DIR/missing-helper" BARISTA_TEST_LOADED_STATUS=1 run_launcher start
assert_actions "$(printf 'launchctl print gui/501/com.example.sketchybar\nlaunchctl bootstrap gui/501 %s/com.example.sketchybar.plist' "$PLIST_DIR")"
assert_state_unchanged
printf 'test_barista_launch.sh: ok\n'
