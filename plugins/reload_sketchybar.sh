#!/bin/bash
# Relaunch SketchyBar via launchctl to avoid lock-file errors.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
AGENT="homebrew.mxcl.sketchybar"
HELPER="${CONFIG_DIR}/helpers/launch_agent_manager.sh"
LABEL="gui/$(id -u)/${AGENT}"
PLIST="${HOME}/Library/LaunchAgents/${AGENT}.plist"
SPACE_REPAIR_DELAY="${BARISTA_SPACE_REPAIR_DELAY:-1.0}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
CORE_ITEM="${BARISTA_CORE_ITEM:-front_app}"
RELOAD_LOCK_DIR="${BARISTA_RELOAD_LOCK_DIR:-${TMPDIR:-/tmp}/barista-sketchybar-reload.lock}"
RELOAD_LOCK_STALE_SECONDS="${BARISTA_RELOAD_LOCK_STALE_SECONDS:-20}"
RELOAD_LOCK_WAIT_SECONDS="${BARISTA_RELOAD_LOCK_WAIT_SECONDS:-20}"
LOCK_HELD=0
WAITED_FOR_LOCK=0

release_reload_lock() {
  if [ "$LOCK_HELD" -eq 1 ]; then
    rmdir "$RELOAD_LOCK_DIR" >/dev/null 2>&1 || true
    LOCK_HELD=0
  fi
}

reload_lock_age() {
  local mtime now
  if ! stat -f %m "$RELOAD_LOCK_DIR" >/dev/null 2>&1; then
    printf '0'
    return 0
  fi
  mtime=$(stat -f %m "$RELOAD_LOCK_DIR" 2>/dev/null || echo 0)
  now=$(date +%s)
  printf '%s' $((now - mtime))
}

acquire_reload_lock() {
  local deadline now age
  deadline=$(( $(date +%s) + RELOAD_LOCK_WAIT_SECONDS ))

  while ! mkdir "$RELOAD_LOCK_DIR" 2>/dev/null; do
    WAITED_FOR_LOCK=1
    age=$(reload_lock_age)
    if [ "$age" -gt "$RELOAD_LOCK_STALE_SECONDS" ]; then
      rmdir "$RELOAD_LOCK_DIR" >/dev/null 2>&1 || true
      continue
    fi
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      return 1
    fi
    sleep 0.1 || true
  done

  LOCK_HELD=1
  return 0
}

wait_for_recent_reload() {
  [ "$WAITED_FOR_LOCK" -eq 1 ] || return 1
  wait_for_item "$CORE_ITEM" 5
}

trap release_reload_lock EXIT

item_loaded() {
  local item_name="${1:-}"
  [ -n "$item_name" ] || return 1
  [ -n "${SKETCHYBAR_BIN:-}" ] || return 1

  local output
  output="$("$SKETCHYBAR_BIN" --query "$item_name" 2>/dev/null || true)"
  [ -n "$output" ]
}

wait_for_item() {
  local item_name="${1:-$CORE_ITEM}"
  local attempts="${2:-5}"

  while [ "$attempts" -gt 0 ]; do
    if item_loaded "$item_name"; then
      return 0
    fi
    sleep 1 || true
    attempts=$((attempts - 1))
  done

  return 1
}

schedule_space_repair() {
  local refresh_script="${CONFIG_DIR}/plugins/refresh_spaces.sh"
  [ -f "$refresh_script" ] || return 0
  nohup env CONFIG_DIR="$CONFIG_DIR" BARISTA_CONFIG_DIR="$CONFIG_DIR" bash -lc \
    "sleep ${SPACE_REPAIR_DELAY}; \"${refresh_script}\" >/dev/null 2>&1 || true" >/dev/null 2>&1 &
}

ensure_live_config() {
  if wait_for_item "$CORE_ITEM"; then
    return 0
  fi

  [ -n "${SKETCHYBAR_BIN:-}" ] || return 1
  "$SKETCHYBAR_BIN" --reload >/dev/null 2>&1 || true
  wait_for_item "$CORE_ITEM"
}

if ! acquire_reload_lock; then
  echo "SketchyBar reload lock timed out: $RELOAD_LOCK_DIR" >&2
  exit 1
fi

if wait_for_recent_reload; then
  exit 0
fi

if [[ -x "$HELPER" ]]; then
  "$HELPER" restart "$AGENT"
  schedule_space_repair
  if ensure_live_config; then
    exit 0
  fi
  echo "SketchyBar restarted, but core item '$CORE_ITEM' did not load." >&2
  exit 1
fi

if launchctl kickstart -k "$LABEL" >/dev/null 2>&1; then
  schedule_space_repair
  if ensure_live_config; then
    exit 0
  fi
  echo "SketchyBar restarted, but core item '$CORE_ITEM' did not load." >&2
  exit 1
fi

# Fallback to unload/load if kickstart failed (e.g., label missing)
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" >/dev/null 2>&1 || true
  launchctl load "$PLIST"
  schedule_space_repair
  if ensure_live_config; then
    exit 0
  fi
  echo "SketchyBar reloaded LaunchAgent, but core item '$CORE_ITEM' did not load." >&2
else
  echo "LaunchAgent plist not found: $PLIST" >&2
  exit 1
fi
