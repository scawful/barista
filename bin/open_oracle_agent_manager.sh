#!/bin/bash

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
STATE_FILE="$CONFIG_DIR/state.json"
CODE_DIR_DEFAULT="${BARISTA_CODE_DIR:-${CODE_DIR:-$HOME/src}}"
LOG_FILE="${TMPDIR:-/tmp}/oracle_agent_manager.log"

MODE="gui"

read_state_value() {
  local query="$1"
  if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
    jq -r "$query" "$STATE_FILE" 2>/dev/null
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hub|--cli)
      MODE="hub"
      ;;
    --gui)
      MODE="gui"
      ;;
  esac
  shift || true
done

STATE_CODE_DIR="$(read_state_value '.paths.code_dir // .paths.code // empty')"
if [[ "$STATE_CODE_DIR" == "null" ]]; then
  STATE_CODE_DIR=""
fi
CODE_DIR="${STATE_CODE_DIR:-$CODE_DIR_DEFAULT}"

resolve_oam_binary() {
  local mode="$1"
  local candidates=()
  if [[ "$mode" == "hub" ]]; then
    candidates=(
      "$CODE_DIR/hobby/oracle-agent-manager/build/oracle_hub"
      "$HOME/src/hobby/oracle-agent-manager/build/oracle_hub"
    )
  else
    candidates=(
      "$CODE_DIR/hobby/oracle-agent-manager/build/oracle_manager_gui"
      "$HOME/src/hobby/oracle-agent-manager/build/oracle_manager_gui"
      "$CODE_DIR/hobby/oracle-agent-manager/oracle_manager_gui"
      "$HOME/src/hobby/oracle-agent-manager/oracle_manager_gui"
    )
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

launch_binary() {
  local bin="$1"
  echo "[oracle-agent-manager] Launching $bin"
  nohup "$bin" >"$LOG_FILE" 2>&1 &
  disown
}

if bin="$(resolve_oam_binary "$MODE" 2>/dev/null)"; then
  launch_binary "$bin"
  exit 0
fi

if [[ "$MODE" == "gui" ]]; then
  echo "[oracle-agent-manager] GUI binary not found, trying oracle_hub" >&2
  if bin="$(resolve_oam_binary hub 2>/dev/null)"; then
    launch_binary "$bin"
    exit 0
  fi
fi

echo "[oracle-agent-manager] No Oracle Agent Manager binary found under $CODE_DIR/hobby/oracle-agent-manager" >&2
exit 1
