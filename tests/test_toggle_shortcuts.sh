#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP"
export BARISTA_CONFIG_DIR="$TMP/runtime with spaces" BARISTA_AGENT_HELPER="$TMP/helper"
export TEST_RUNTIME="$TMP/service" TEST_LOG="$TMP/actions"
TEST_REAL_PYTHON="$(command -v python3)"
export TEST_REAL_PYTHON
LABEL=com.koekeishiya.skhd
OTHER_LABEL=homebrew.mxcl.skhd
mkdir -p "$TMP/bin" "$TEST_RUNTIME" "$BARISTA_CONFIG_DIR" "$HOME/Library/LaunchAgents"
unset BARISTA_SHORTCUT_OPERATION_LOCKED BARISTA_SKHD_LABEL

cat > "$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
# Global read-only status can see other users; mutation checks only this user.
if [[ "$1" != -u && -f "$TEST_RUNTIME/other-user" ]]; then exit 0; fi
[[ -f "$TEST_RUNTIME/foreign" ]] && exit 0
for label in com.koekeishiya.skhd homebrew.mxcl.skhd; do
  [[ -f "$TEST_RUNTIME/$label.pid" ]] && exit 0
done
exit 1
STUB
cat > "$TMP/bin/launchctl" <<'STUB'
#!/bin/bash
action="$1"
label="${2##*/}"
case "$action" in
  print)
    [[ -f "$TEST_RUNTIME/$label.loaded" ]] || exit 113
    printf 'gui/test/%s = {\n' "$label"
    if [[ -f "$TEST_RUNTIME/$label.pid" ]]; then
      printf '\tstate = running\n\tpid = %s\n' "$(cat "$TEST_RUNTIME/$label.pid")"
    else
      printf '\tstate = %s\n' "${TEST_JOB_STATE:-waiting}"
    fi
    printf '}\n' ;;
  print-disabled)
    [[ "${TEST_READ_POLICY_FAIL:-0}" != 1 ]] || exit 19
    printf 'disabled services = {\n'
    for label in com.koekeishiya.skhd homebrew.mxcl.skhd; do
      [[ -f "$TEST_RUNTIME/$label.policy" ]] || continue
      value="$(cat "$TEST_RUNTIME/$label.policy")"
      if [[ "${TEST_POLICY_FORMAT:-words}" == boolean ]]; then
        if [[ "$value" == enabled ]]; then value=false; else value=true; fi
      fi
      printf '\t"%s" => %s\n' "$label" "$value"
    done
    printf '}\n' ;;
  enable|disable)
    printf '%s %s\n' "$action" "$2" >> "$TEST_LOG"
    [[ "${TEST_LAUNCHCTL_FAIL:-}" != "$action" ]] || exit 13
    printf '%sd\n' "$action" > "$TEST_RUNTIME/$label.policy" ;;
  *) printf 'Unexpected launchctl action: %s\n' "$*" >&2; exit 99 ;;
esac
STUB
cat > "$TMP/bin/sleep" <<'STUB'
#!/bin/bash
# Verification retries are immediate; concurrency delays use /bin/sleep.
exit 0
STUB
cat > "$TMP/bin/python3" <<'STUB'
#!/bin/bash
if [[ "${3:-}" == shortcuts-state ]]; then
  printf 'save-begin %s\n' "$4" >> "$TEST_LOG"
  if [[ "${TEST_SAVE_DELAY:-}" == "$4" ]]; then
    touch "$TEST_RUNTIME/save-ready"
    /bin/sleep 0.5
  fi
  [[ "${TEST_SAVE_FAIL:-0}" != 1 ]] || exit 23
fi
exec "$TEST_REAL_PYTHON" "$@"
STUB
cat > "$BARISTA_AGENT_HELPER" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_LOG"
[[ "${TEST_SERVICE_FAIL:-0}" != 1 ]] || exit 7
[[ "${TEST_NO_TRANSITION:-0}" != 1 ]] || exit 0
case "$1" in
  start|restart)
    touch "$TEST_RUNTIME/$2.loaded"
    [[ -f "$TEST_RUNTIME/$2.pid" ]] || printf '4242\n' > "$TEST_RUNTIME/$2.pid" ;;
  stop) rm -f "$TEST_RUNTIME/$2.loaded" "$TEST_RUNTIME/$2.pid" ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/"* "$BARISTA_AGENT_HELPER"
export PATH="$TMP/bin:$PATH"

run() { /bin/bash "$ROOT/scripts/toggle_shortcuts.sh" "$@"; }
state() {
  python3 -c 'import json,os; s=json.load(open(os.environ["BARISTA_CONFIG_DIR"]+"/state.json")); assert s["keep"]=="unchanged"; print(str(s["toggles"]["yabai_shortcuts"]).lower())'
}
policy() { cat "$TEST_RUNTIME/$LABEL.policy"; }
write_plist() {
  python3 -c 'import plistlib,sys; plistlib.dump({"Label":sys.argv[2],"Disabled":sys.argv[3]=="true"},open(sys.argv[1],"wb"))' \
    "$HOME/Library/LaunchAgents/$1.plist" "$1" "${2:-false}"
}
reset_fixture() {
  rm -f "$TEST_RUNTIME/"* "$HOME/Library/LaunchAgents/$OTHER_LABEL.plist"
  write_plist "$LABEL"
  printf '{"keep":"unchanged","toggles":{"yabai_shortcuts":false}}' > "$BARISTA_CONFIG_DIR/state.json"
  printf 'disabled\n' > "$TEST_RUNTIME/$LABEL.policy"
  : > "$TEST_LOG"
}
expect_failure() {
  local expected="$1" actual=0
  shift
  "$@" > "$TMP/error" 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    cat "$TMP/error" >&2
    printf 'Expected status %s; got %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}
wait_for_save() {
  local attempt
  for ((attempt=0; attempt<100; attempt++)); do
    [[ ! -f "$TEST_RUNTIME/save-ready" ]] || return 0
    /bin/sleep 0.01
  done
  printf 'Timed out waiting for test transaction\n' >&2
  return 1
}

# Status does not read state or mutate launchctl, including corrupt state.
reset_fixture
cp "$BARISTA_CONFIG_DIR/state.json" "$TMP/before"
[[ "$(run status)" == 'skhd stopped' ]]
touch "$TEST_RUNTIME/other-user"
[[ "$(run status)" == 'skhd running' ]]
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ ! -s "$TEST_LOG" ]]
printf '{broken' > "$BARISTA_CONFIG_DIR/state.json"
[[ "$(run status)" == 'skhd running' ]]
expect_failure 1 run on
[[ ! -s "$TEST_LOG" ]]
cmp "$BARISTA_CONFIG_DIR/state.json" <(printf '{broken')

# On is idempotent for the selected job; another user's process cannot block it.
reset_fixture
touch "$TEST_RUNTIME/other-user"
run on > "$TMP/result"
[[ -f "$TEST_RUNTIME/$LABEL.pid" && "$(state)" == true && "$(policy)" == enabled ]]
grep -q '^enable gui/' "$TEST_LOG"
grep -q "^start $LABEL$" "$TEST_LOG"
grep -q "^skhd running ($LABEL)$" "$TMP/result"
printf '5678\n' > "$TEST_RUNTIME/$LABEL.pid"
: > "$TEST_LOG"
run on >/dev/null
[[ "$(cat "$TEST_RUNTIME/$LABEL.pid")" == 5678 ]]
grep -q "^start $LABEL$" "$TEST_LOG"

# Off verifies only the selected job, even with an unrelated process still up.
touch "$TEST_RUNTIME/foreign"
run off > "$TMP/result"
[[ ! -f "$TEST_RUNTIME/$LABEL.pid" && "$(state)" == false && "$(policy)" == disabled ]]
[[ -f "$TEST_RUNTIME/foreign" && "$(run status)" == 'skhd running' ]]
grep -q '^disable gui/' "$TEST_LOG"
grep -q "^stop $LABEL$" "$TEST_LOG"
grep -q "^skhd stopped ($LABEL)$" "$TMP/result"
: > "$TEST_LOG"
expect_failure 1 run on
grep -q "outside $LABEL" "$TMP/error"
[[ ! -s "$TEST_LOG" && "$(policy)" == disabled && "$(state)" == false ]]

# A launchctl state without a PID is not evidence that the selected job runs.
reset_fixture
touch "$TEST_RUNTIME/$LABEL.loaded"
TEST_JOB_STATE=running TEST_NO_TRANSITION=1 expect_failure 1 run on
grep -q 'did not reach the requested state' "$TMP/error"
[[ "$(policy)" == disabled && "$(state)" == false ]]

# Failed start and verification restore policy and preserve saved state bytes.
reset_fixture
cp "$BARISTA_CONFIG_DIR/state.json" "$TMP/before"
TEST_SERVICE_FAIL=1 expect_failure 7 run on
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == disabled ]]
TEST_NO_TRANSITION=1 expect_failure 1 run on
grep -q 'did not reach the requested state' "$TMP/error"
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == disabled ]]
TEST_SAVE_FAIL=1 expect_failure 23 run on
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == disabled ]]

# Reverse direction restores an enabled policy, including boolean output.
reset_fixture
TEST_POLICY_FORMAT=boolean run on >/dev/null
cp "$BARISTA_CONFIG_DIR/state.json" "$TMP/before"
TEST_POLICY_FORMAT=boolean TEST_SERVICE_FAIL=1 expect_failure 7 run off
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == enabled && -f "$TEST_RUNTIME/$LABEL.pid" ]]
TEST_NO_TRANSITION=1 expect_failure 1 run off
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == enabled && -f "$TEST_RUNTIME/$LABEL.pid" ]]
TEST_SAVE_FAIL=1 expect_failure 23 run off
cmp "$TMP/before" "$BARISTA_CONFIG_DIR/state.json"
[[ "$(policy)" == enabled ]]

# Read/mutation errors are fatal; rollback failure preserves the first code.
reset_fixture
TEST_READ_POLICY_FAIL=1 expect_failure 1 run on
[[ ! -s "$TEST_LOG" && "$(policy)" == disabled ]]
TEST_LAUNCHCTL_FAIL=enable expect_failure 13 run on
[[ "$(policy)" == disabled && "$(state)" == false ]]
TEST_SERVICE_FAIL=1 TEST_LAUNCHCTL_FAIL=disable expect_failure 7 run on
grep -q 'rollback failed' "$TMP/error"
[[ "$(state)" == false ]]

# No override: rollback restores the plist's effective Disabled preference.
reset_fixture
write_plist "$LABEL" true
rm -f "$TEST_RUNTIME/$LABEL.policy"
TEST_SERVICE_FAIL=1 expect_failure 7 run on
[[ "$(policy)" == disabled && "$(state)" == false ]]
write_plist "$LABEL" false
rm -f "$TEST_RUNTIME/$LABEL.policy"
TEST_SERVICE_FAIL=1 expect_failure 7 run off
[[ "$(policy)" == enabled && "$(state)" == false ]]

# Select one loaded job, reject ambiguity, and keep compatibility entrypoint.
reset_fixture
run toggle >/dev/null
[[ -f "$TEST_RUNTIME/$LABEL.pid" && "$(state)" == true ]]
/bin/bash "$ROOT/scripts/toggle_yabai_shortcuts.sh" restart >/dev/null
grep -q "^restart $LABEL$" "$TEST_LOG"
write_plist "$OTHER_LABEL"
run on >/dev/null
touch "$TEST_RUNTIME/$OTHER_LABEL.loaded"
: > "$TEST_LOG"
expect_failure 1 run off
grep -q 'More than one skhd service is loaded' "$TMP/error"
[[ ! -s "$TEST_LOG" && -f "$TEST_RUNTIME/$LABEL.pid" ]]
BARISTA_SKHD_LABEL="$LABEL" run off >/dev/null
rm -f "$TEST_RUNTIME/$OTHER_LABEL.loaded"
: > "$TEST_LOG"
expect_failure 1 run on
grep -q 'Expected one installed skhd LaunchAgent; found 2' "$TMP/error"
[[ ! -s "$TEST_LOG" ]]

# Serialize final write: Off cannot slip between On verification and saving.
reset_fixture
TEST_SAVE_DELAY=true run on > "$TMP/on-result" 2>&1 &
on_pid=$!
wait_for_save
mkdir -p "$TMP/other-temp"
TMPDIR="$TMP/other-temp" run off > "$TMP/off-result" 2>&1 &
off_pid=$!
wait "$on_pid"
wait "$off_pid"
[[ ! -f "$TEST_RUNTIME/$LABEL.pid" && "$(state)" == false && "$(policy)" == disabled ]]
python3 - "$TEST_LOG" <<'PY'
import pathlib,sys
events=pathlib.Path(sys.argv[1]).read_text().splitlines()
assert events.index("save-begin true") < next(i for i,x in enumerate(events) if x.startswith("disable "))
assert events[-1] == "save-begin false", events
PY

# A bounded waiter fails without changing the active operation or policy.
reset_fixture
TEST_SAVE_DELAY=true run on > "$TMP/on-result" 2>&1 &
on_pid=$!
wait_for_save
BARISTA_SHORTCUT_LOCK_TIMEOUT=0.01 expect_failure 1 run off
grep -q 'another shortcut action is still running' "$TMP/error"
wait "$on_pid"
[[ -f "$TEST_RUNTIME/$LABEL.pid" && "$(state)" == true && "$(policy)" == enabled ]]
if grep -q '^disable ' "$TEST_LOG"; then exit 1; fi
run off >/dev/null
[[ "$(state)" == false && "$(policy)" == disabled ]]
printf 'test_toggle_shortcuts.sh: ok\n'
