#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"

ORACLE_EMACS_APP="${ORACLE_EMACS_APP:-Emacs}"
ORACLE_MESEN_APP="${ORACLE_MESEN_APP:-Mesen2 OOS}"
ORACLE_YAZE_APP="${ORACLE_YAZE_APP:-Yaze}"

ORACLE_EMACS_SPACE="${ORACLE_EMACS_SPACE:-4}"
ORACLE_MESEN_SPACE="${ORACLE_MESEN_SPACE:-3}"
ORACLE_YAZE_SPACE="${ORACLE_YAZE_SPACE:-5}"

ORACLE_LAYOUT_OPEN_APPS="${ORACLE_LAYOUT_OPEN_APPS:-1}"

usage() {
  cat <<'EOF'
Restore the Oracle development layout in yabai.

Usage:
  oracle_layout.sh restore

Environment overrides:
  ORACLE_EMACS_APP
  ORACLE_MESEN_APP
  ORACLE_YAZE_APP
  ORACLE_EMACS_SPACE
  ORACLE_MESEN_SPACE
  ORACLE_YAZE_SPACE
  ORACLE_LAYOUT_OPEN_APPS=0|1
EOF
}

require_tools() {
  if [[ -z "${YABAI_BIN}" ]]; then
    echo "yabai not found in PATH." >&2
    exit 1
  fi
  if [[ -z "${JQ_BIN}" ]]; then
    echo "jq is required for oracle_layout.sh." >&2
    exit 1
  fi
}

launch_if_missing() {
  local app_name="$1"
  if [[ "${ORACLE_LAYOUT_OPEN_APPS}" != "1" ]]; then
    return 0
  fi
  if ! osascript -e "tell application \"System Events\" to (name of processes) contains \"${app_name}\"" 2>/dev/null | grep -q "true"; then
    open -a "${app_name}" >/dev/null 2>&1 || true
    sleep 0.6
  fi
}

window_id_for_app() {
  local app_name="$1"
  "${YABAI_BIN}" -m query --windows 2>/dev/null \
    | "${JQ_BIN}" -r --arg app "${app_name}" 'map(select(.app == $app)) | first | .id // empty' \
    | head -n 1
}

move_app_to_space() {
  local app_name="$1"
  local target_space="$2"
  local window_id=""

  launch_if_missing "${app_name}"
  window_id="$(window_id_for_app "${app_name}")"
  if [[ -z "${window_id}" ]]; then
    return 0
  fi

  "${YABAI_BIN}" -m window "${window_id}" --space "${target_space}" >/dev/null 2>&1 || true
}

focus_app() {
  local app_name="$1"
  local window_id=""
  window_id="$(window_id_for_app "${app_name}")"
  if [[ -n "${window_id}" ]]; then
    "${YABAI_BIN}" -m window "${window_id}" --focus >/dev/null 2>&1 || true
    return 0
  fi
  open -a "${app_name}" >/dev/null 2>&1 || true
}

restore_layout() {
  require_tools

  move_app_to_space "${ORACLE_EMACS_APP}" "${ORACLE_EMACS_SPACE}"
  move_app_to_space "${ORACLE_MESEN_APP}" "${ORACLE_MESEN_SPACE}"
  move_app_to_space "${ORACLE_YAZE_APP}" "${ORACLE_YAZE_SPACE}"

  "${YABAI_BIN}" -m space --focus "${ORACLE_MESEN_SPACE}" >/dev/null 2>&1 || true
  focus_app "${ORACLE_MESEN_APP}"
}

command="${1:-restore}"

case "${command}" in
  restore)
    restore_layout
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: ${command}" >&2
    usage >&2
    exit 1
    ;;
esac
