#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUNTIME_DIR="$TMP_DIR/config/sketchybar"
CODE_DIR="$TMP_DIR/company-checkout"
BIN_DIR="$TMP_DIR/company-bin"
dry_output="$("$ROOT_DIR/scripts/bootstrap_machine.sh" \
  --runtime-dir "$RUNTIME_DIR" \
  --profile restricted-work \
  --dry-run)"
grep -Fq "runtime=$RUNTIME_DIR" <<<"$dry_output"
test ! -e "$RUNTIME_DIR"

HOME="$TMP_DIR/home" "$ROOT_DIR/scripts/bootstrap_machine.sh" \
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

AGENT_DIR="$TMP_DIR/agents"
LOG_DIR="$TMP_DIR/logs"
BARISTA_LAUNCH_AGENT_DIR="$AGENT_DIR" \
BARISTA_LOG_DIR="$LOG_DIR" \
  "$ROOT_DIR/bin/install-launch-agent" \
    --config-dir "$RUNTIME_DIR" \
    --code-dir "$CODE_DIR" \
    --bin-dir "$BIN_DIR" \
    --no-start >/dev/null

CONTROL_PLIST="$AGENT_DIR/dev.barista.control.plist"
test -f "$CONTROL_PLIST"
plutil -extract ProgramArguments.2 raw "$CONTROL_PLIST" \
  | grep -Fq "$RUNTIME_DIR/launch_agents/barista-launch.sh start"
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

printf 'test_portable_bootstrap.sh: ok\n'
