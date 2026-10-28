#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_DIR="$TMP_DIR/home"
RUNTIME_DIR="$HOME_DIR/config with spaces/sketchybar"
CODE_DIR="$HOME_DIR/company checkout"
BIN_DIR="$HOME_DIR/.local/bin with spaces"
dry_output="$(/bin/bash "$ROOT_DIR/scripts/bootstrap_machine.sh" \
  --runtime-dir "$RUNTIME_DIR" \
  --profile restricted-work \
  --dry-run)"
grep -Fq "runtime=$RUNTIME_DIR" <<<"$dry_output"
test ! -e "$RUNTIME_DIR"

HOME="$HOME_DIR" "$ROOT_DIR/scripts/bootstrap_machine.sh" \
  --runtime-dir "$RUNTIME_DIR" \
  --code-dir "$CODE_DIR" \
  --profile restricted-work >/dev/null

test -f "$RUNTIME_DIR/main.lua"
test -f "$RUNTIME_DIR/state.json"
test -f "$RUNTIME_DIR/data/machine.local.json"
jq -e '.profile == "work" and .modes.runtime_backend == "lua"' \
  "$RUNTIME_DIR/state.json" >/dev/null
jq -e --arg code_dir "$CODE_DIR" '.paths.code_dir == $code_dir' \
  "$RUNTIME_DIR/state.json" >/dev/null
jq -e '.profile_variant == "restricted-work" and .restricted == true' \
  "$RUNTIME_DIR/data/machine.local.json" >/dev/null

if "$ROOT_DIR/scripts/bootstrap_machine.sh" \
  --runtime-dir "$RUNTIME_DIR" \
  --profile work >/dev/null 2>&1; then
  echo "bootstrap unexpectedly replaced an existing runtime" >&2
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
  AGENT_DIR="$TMP_DIR/agents"
  LOG_DIR="$TMP_DIR/logs"
  # Literal tildes exercise the installer's own path expansion.
  # shellcheck disable=SC2088
  HOME="$HOME_DIR" BARISTA_LAUNCH_AGENT_DIR="$AGENT_DIR" \
  BARISTA_LOG_DIR="$LOG_DIR" \
    "$ROOT_DIR/bin/install-launch-agent" \
      --config-dir '~/config with spaces/sketchybar' \
      --code-dir '~/company checkout' \
      --bin-dir '~/.local/bin with spaces' \
      --mouse-buttons --no-start >/dev/null

  CONTROL_PLIST="$AGENT_DIR/dev.barista.control.plist"
  test -f "$CONTROL_PLIST"
  python3 - "$CONTROL_PLIST" "$AGENT_DIR/dev.barista.mouse-buttons.plist" "$RUNTIME_DIR" <<'PYPLIST'
import plistlib, sys
control_path, mouse_path, runtime = sys.argv[1:]
with open(control_path, "rb") as handle:
    control = plistlib.load(handle)
with open(mouse_path, "rb") as handle:
    mouse = plistlib.load(handle)
assert control["ProgramArguments"] == ["/bin/bash", runtime + "/launch_agents/barista-launch.sh", "start"]
assert mouse["ProgramArguments"] == ["/bin/bash", runtime + "/scripts/start_mouse_button_mapper.sh"]
assert "~" not in control["EnvironmentVariables"]["BARISTA_CONFIG_DIR"]
PYPLIST
  plutil -extract StandardOutPath raw "$CONTROL_PLIST" \
    | grep -Fq "$LOG_DIR/barista-control.out.log"
  plutil -extract EnvironmentVariables.BARISTA_CONFIG_DIR raw "$CONTROL_PLIST" \
    | grep -Fq "$RUNTIME_DIR"
  plutil -extract EnvironmentVariables.BARISTA_CODE_DIR raw "$CONTROL_PLIST" \
    | grep -Fq "$CODE_DIR"
  plutil -extract EnvironmentVariables.PATH raw "$CONTROL_PLIST" \
    | grep -Fq "$BIN_DIR:"
  if grep -Fq '/Users/scawful' "$CONTROL_PLIST"; then
    echo "portable plist contains a personal path" >&2
    exit 1
  fi

  # A validation failure must preserve the previously installed plist.
  STUB_BIN="$TMP_DIR/install-stubs"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/plutil" <<'PLUTIL'
#!/bin/bash
if [ "${BARISTA_TEST_FAIL_VALIDATION:-0}" = 1 ] && [ "${1:-}" = -lint ]; then
  echo 'Fixture plist validation failed' >&2
  exit 17
fi
exec /usr/bin/plutil "$@"
PLUTIL
  cat > "$STUB_BIN/launchctl" <<'LAUNCHCTL'
#!/bin/bash
printf '%s\n' "$*" >> "$BARISTA_TEST_LAUNCHCTL_LOG"
[ "${1:-}" != bootstrap ]
LAUNCHCTL
  chmod +x "$STUB_BIN/plutil" "$STUB_BIN/launchctl"
  cp "$CONTROL_PLIST" "$TMP_DIR/installed.before.plist"
  if HOME="$HOME_DIR" PATH="$STUB_BIN:$PATH" \
    BARISTA_LAUNCH_AGENT_DIR="$AGENT_DIR" BARISTA_LOG_DIR="$LOG_DIR" \
    BARISTA_TEST_FAIL_VALIDATION=1 \
    "$ROOT_DIR/bin/install-launch-agent" --config-dir "$RUNTIME_DIR" \
      --no-start > "$TMP_DIR/validation.out" 2> "$TMP_DIR/validation.err"; then
    echo 'FAIL: installer ignored failed plist validation' >&2
    exit 1
  fi
  grep -Fq 'Fixture plist validation failed' "$TMP_DIR/validation.err" || {
    cat "$TMP_DIR/validation.out" "$TMP_DIR/validation.err" >&2
    exit 1
  }
  cmp "$TMP_DIR/installed.before.plist" "$CONTROL_PLIST"
  python3 - "$AGENT_DIR" <<'PYFILES'
from pathlib import Path
import sys
root = Path(sys.argv[1])
assert not list(root.glob("dev.barista.control.plist.backup.*")), "failed rendering must not create a backup"
assert not list(root.glob(".dev.barista.control.*")), "failed rendering must clean its staging file"
PYFILES

  # A bootstrap failure reports failure even when the rendered plist is valid.
  if HOME="$HOME_DIR" PATH="$STUB_BIN:$PATH" \
    BARISTA_LAUNCH_AGENT_DIR="$AGENT_DIR" BARISTA_LOG_DIR="$LOG_DIR" \
    BARISTA_TEST_LAUNCHCTL_LOG="$TMP_DIR/launchctl.log" \
    "$ROOT_DIR/bin/install-launch-agent" --config-dir "$RUNTIME_DIR" \
      > "$TMP_DIR/bootstrap.out" 2> "$TMP_DIR/bootstrap.err"; then
    echo 'FAIL: installer claimed success after launchctl bootstrap failed' >&2
    exit 1
  fi
  grep -Fq 'was rendered but launchctl could not load it' "$TMP_DIR/bootstrap.out" || {
    cat "$TMP_DIR/bootstrap.out" "$TMP_DIR/bootstrap.err" >&2
    exit 1
  }
  if grep -Fq 'Launch agent installation complete!' "$TMP_DIR/bootstrap.out"; then
    echo 'FAIL: failed bootstrap printed the success summary' >&2
    exit 1
  fi

fi

printf 'test_portable_bootstrap.sh: ok\n'
