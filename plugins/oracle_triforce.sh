#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-triforce}"
TRIFORCE_WIDGET_BIN="${BARISTA_TRIFORCE_WIDGET_BIN:-}"
ORACLE_REPO_PATH="${BARISTA_ORACLE_REPO_PATH:-}"
ORACLE_STATUS_BIN="${BARISTA_ORACLE_STATUS_BIN:-}"
PYTHON_BIN="${BARISTA_PYTHON_BIN:-$(command -v python3 2>/dev/null || true)}"
STATUS_TIMEOUT="${BARISTA_ORACLE_STATUS_TIMEOUT:-4}"
LABEL_OVERRIDE="${BARISTA_TRIFORCE_LABEL_OVERRIDE:-}"
REFRESH_LOCK_FILE="${BARISTA_TRIFORCE_REFRESH_LOCK_FILE:-${TMPDIR:-/tmp}/barista_triforce_refresh.${UID:-0}.lock}"

# The packet owns its ROM, checkpoint and private Mesen profile. Keep this
# explicit launcher separate from both oos-rc-play and the newest Dev build.
if [ "${1:-}" = "launch_ganondorf" ]; then
  launcher="${BARISTA_GANONDORF_LAUNCHER:-}"
  if [ -z "$launcher" ] || [ ! -f "$launcher" ] || [ ! -x "$launcher" ]; then
    printf 'Ganondorf launcher is unavailable: %s\n' "$launcher" >&2
    exit 1
  fi
  exec "$launcher"
fi

# Invoked indirectly by the EXIT trap in refresh_triforce.
# shellcheck disable=SC2329
release_refresh_lock() {
  case "${REFRESH_LOCK_KIND:-}" in
    file) rm -f -- "$REFRESH_LOCK_FILE" ;;
    dir) rmdir -- "$REFRESH_LOCK_FILE" 2>/dev/null || true ;;
  esac
}

acquire_refresh_lock() {
  REFRESH_LOCK_KIND=""
  if command -v shlock >/dev/null 2>&1; then
    if ! shlock -f "$REFRESH_LOCK_FILE" -p $$ >/dev/null 2>&1; then
      return 1
    fi
    REFRESH_LOCK_KIND="file"
    return 0
  fi
  if ! mkdir "$REFRESH_LOCK_FILE" 2>/dev/null; then
    return 1
  fi
  REFRESH_LOCK_KIND="dir"
}

refresh_triforce() (
  local -a update_args=()
  local argument

  if ! acquire_refresh_lock; then
    exit 0
  fi
  trap release_refresh_lock EXIT
  trap 'exit 143' HUP INT TERM

  if [ -n "$ORACLE_STATUS_BIN" ] && [ -x "$ORACLE_STATUS_BIN" ] && [ -n "$PYTHON_BIN" ] && [ -x "$PYTHON_BIN" ]; then
    while IFS= read -r -d '' argument; do
      update_args+=("$argument")
    done < <(
      "$PYTHON_BIN" -c '
import json
import os
import signal
import subprocess
import sys


def mapping(value):
    return value if isinstance(value, dict) else {}


def string(value):
    if not isinstance(value, str):
        return ""
    return value.replace("\0", " ").replace("\r", " ").replace("\n", " ")


def emit(*arguments):
    output = sys.stdout.buffer
    for argument in arguments:
        output.write(argument.encode("utf-8") + b"\0")


name, status_bin, repo_path, timeout_text, label_override = sys.argv[1:6]
try:
    timeout = min(max(float(timeout_text), 0.1), 15.0)
except (TypeError, ValueError):
    timeout = 4.0

try:
    process = subprocess.Popen(
        [status_bin, "status-json", "--barista"],
        cwd=repo_path if os.path.isdir(repo_path) else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
except OSError:
    raise SystemExit(0)

try:
    payload, _ = process.communicate(timeout=timeout)
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.communicate(timeout=0.2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
    raise SystemExit(0)

if process.returncode != 0 or len(payload) > 1024 * 1024:
    raise SystemExit(0)
try:
    data = mapping(json.loads(payload.decode("utf-8")))
except (UnicodeDecodeError, TypeError, ValueError):
    raise SystemExit(0)

finish = mapping(data.get("finish_line"))
focus = mapping(finish.get("focus"))

status_label = label_override or string(finish.get("status_line")) or string(focus.get("label")) or "Oracle"
level = string(finish.get("alerts_level")) or "ok"
color = {
    "ok": "0xffa6e3a1",
    "warn": "0xfff9e2af",
    "error": "0xfff38ba8",
}.get(level, "0xff89b4fa")

emit(
    "--set", name,
    f"label={status_label[:24]}", f"icon.color={color}", f"label.color={color}",
    "--set", "oracle.triforce.header", f"icon.color={color}",
)
' "$NAME" "$ORACLE_STATUS_BIN" "$ORACLE_REPO_PATH" "$STATUS_TIMEOUT" "$LABEL_OVERRIDE" 2>/dev/null
    )

    if [ "${#update_args[@]}" -gt 0 ]; then
      update_args+=(--set oracle.triforce.play.launch_test "label=$(dev_label)")
      local play_fields
      play_fields="$(play_status_fields)"
      if [ -n "$play_fields" ]; then
        update_args+=(--set oracle.triforce.play.play_status
          "icon=$(play_status_icon "${play_fields%% *}")" "label=${play_fields#* }")
      fi
      sketchybar "${update_args[@]}"
    fi
    return
  fi

  if [ -n "$TRIFORCE_WIDGET_BIN" ] && [ -x "$TRIFORCE_WIDGET_BIN" ]; then
    "$TRIFORCE_WIDGET_BIN"
  fi
)

# "<state> <short label>" for the Mesen play window, from Oracle's
# Scripts/Mesen2/oos_play.py; empty when unavailable or slower than STATUS_TIMEOUT.
play_status_fields() {
  local repo="${ORACLE_REPO_PATH:-$HOME/src/hobby/oracle-of-secrets}"
  local play_script="$repo/Scripts/Mesen2/oos_play.py"
  [ -f "$play_script" ] && [ -n "$PYTHON_BIN" ] || return 0
  "$PYTHON_BIN" - "$play_script" "$STATUS_TIMEOUT" 2>/dev/null <<'PY' || true
import json, subprocess, sys
try:
    out = subprocess.run([sys.executable, sys.argv[1], "--status", "--json"], capture_output=True,
                         text=True, timeout=float(sys.argv[2]), check=True).stdout
    status = json.loads(out)
    print(status["state"], status["short"][:14])
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
    pass
PY
}

play_status_icon() {
  case "$1" in
    current) printf '󰍹' ;;   # window open on the latest build
    outdated) printf '󰚰' ;;  # a newer build is ready
    *) printf '󰶐' ;;         # window closed
  esac
}

# Dev row label: the newest Roms/TestBuilds build, the one
# `oos-triforce.sh launch test` opens (newest oos*x.sfc by mtime). Sent in the
# refresh's single batched SketchyBar call.
dev_label() {
  local repo="${ORACLE_REPO_PATH:-$HOME/src/hobby/oracle-of-secrets}"
  local newest name label="Dev build"
  # shellcheck disable=SC2012
  newest=$(ls -t "$repo"/Roms/TestBuilds/*/oos*x.sfc 2>/dev/null | head -n 1) || true
  if [ -n "$newest" ]; then
    name="${newest%/*}"
    name="${name##*/}"
    name=$(printf '%s' "$name" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}$//')
    label="Dev $name"
  fi
  printf '%s' "${label:0:28}"
}

case "${SENDER:-}" in
  "mouse.entered")
    highlight_with_timeout "$NAME" "$(anchor_hover_props)" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    exit 0
    ;;
  "mouse.exited.global")
    clear_highlight "$NAME" "$(anchor_idle_props)"
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

case "${BARISTA_TRIFORCE_ACTION:-}" in
  click) exit 0 ;;
esac

case "${SENDER:-}" in
  ""|forced|popup_refresh|system_woke)
    refresh_triforce
    ;;
esac

exit 0
