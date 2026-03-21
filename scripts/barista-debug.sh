#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"

SET_BACKEND=""
SET_PANEL_MODE=""
RELOAD=0
RUN_DOCTOR=1
FIX=0
SHOW_LOGS=0

usage() {
  cat <<EOF
Usage: $0 [options]

Debug and switch Barista into a no-C++ workflow when needed.

Options:
  --lua-only           Persist Lua runtime backend and prefer the TUI panel
  --auto               Restore automatic helper/runtime detection
  --panel-mode <mode>  Override control panel mode (native|tui|imgui|custom)
  --reload             Reload SketchyBar after applying changes
  --fix                Run barista-doctor --fix after applying changes
  --no-doctor          Skip barista-doctor
  --logs               Show recent control-panel and launch-agent logs
  --state <path>       state.json path (default: ~/.config/sketchybar/state.json)
  --config-dir <path>  Config dir (default: ~/.config/sketchybar)
EOF
}

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    ~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --lua-only)
      SET_BACKEND="lua"
      if [ -z "$SET_PANEL_MODE" ]; then
        SET_PANEL_MODE="tui"
      fi
      shift
      ;;
    --auto)
      SET_BACKEND="auto"
      shift
      ;;
    --panel-mode)
      SET_PANEL_MODE="${2:-}"
      shift 2
      ;;
    --reload)
      RELOAD=1
      shift
      ;;
    --fix)
      FIX=1
      shift
      ;;
    --no-doctor)
      RUN_DOCTOR=0
      shift
      ;;
    --logs)
      SHOW_LOGS=1
      shift
      ;;
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

CONFIG_DIR="$(expand_home "$CONFIG_DIR")"
STATE_FILE="$(expand_home "$STATE_FILE")"

show_logs() {
  local log_files=(
    "${TMPDIR:-/tmp}/barista_control_panel.log"
    "/tmp/barista.control.out.log"
    "/tmp/barista.control.err.log"
  )
  local file
  for file in "${log_files[@]}"; do
    [ -f "$file" ] || continue
    printf '\n== %s ==\n' "$file"
    tail -n 40 "$file" || true
  done
}

if [ -n "$SET_BACKEND" ] || [ -n "$SET_PANEL_MODE" ]; then
  setup_args=(--state "$STATE_FILE" --yes --no-reload)
  if [ -n "$SET_PANEL_MODE" ]; then
    setup_args+=(--skip-fonts --panel-mode "$SET_PANEL_MODE")
  else
    setup_args+=(--skip-fonts --skip-panel)
  fi
  if [ -n "$SET_BACKEND" ]; then
    setup_args+=(--runtime-backend "$SET_BACKEND")
  fi
  "$ROOT_DIR/scripts/setup_machine.sh" "${setup_args[@]}"
fi

if [ "$RUN_DOCTOR" -eq 1 ]; then
  doctor_args=(--config-dir "$CONFIG_DIR" --state "$STATE_FILE" --report)
  if [ "$FIX" -eq 1 ]; then
    doctor_args+=(--fix)
  fi
  "$ROOT_DIR/scripts/barista-doctor.sh" "${doctor_args[@]}" || true
fi

if [ "$RELOAD" -eq 1 ] && command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
  printf '[debug] reloaded sketchybar\n'
fi

if [ "$SHOW_LOGS" -eq 1 ]; then
  show_logs
fi
