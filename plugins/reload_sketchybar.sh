#!/bin/bash
# Relaunch SketchyBar via launchctl to avoid lock-file errors.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
AGENT="homebrew.mxcl.sketchybar"
HELPER="${CONFIG_DIR}/helpers/launch_agent_manager.sh"
LABEL="gui/$(id -u)/${AGENT}"
PLIST="${HOME}/Library/LaunchAgents/${AGENT}.plist"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
CORE_ITEM="${BARISTA_CORE_ITEM:-front_app}"
CORE_ITEM_WAIT_ATTEMPTS="${BARISTA_CORE_ITEM_WAIT_ATTEMPTS:-10}"
case "$CORE_ITEM_WAIT_ATTEMPTS" in
  ""|*[!0-9]*) CORE_ITEM_WAIT_ATTEMPTS=10 ;;
  *) CORE_ITEM_WAIT_ATTEMPTS=$((10#$CORE_ITEM_WAIT_ATTEMPTS)) ;;
esac
RELOAD_LOCK_DIR="${BARISTA_RELOAD_LOCK_DIR:-${TMPDIR:-/tmp}/barista-sketchybar-reload.lock}"
RELOAD_LOCK_OWNER_FILE="$RELOAD_LOCK_DIR/owner_pid"
RELOAD_LOCK_STALE_SECONDS="${BARISTA_RELOAD_LOCK_STALE_SECONDS:-20}"
RELOAD_LOCK_WAIT_SECONDS="${BARISTA_RELOAD_LOCK_WAIT_SECONDS:-$((CORE_ITEM_WAIT_ATTEMPTS * 2 + 15))}"
LOCK_HELD=0
WAITED_FOR_LOCK=0

release_reload_lock() {
  if [ "$LOCK_HELD" -eq 1 ]; then
    local owner_pid
    owner_pid="$(cat "$RELOAD_LOCK_OWNER_FILE" 2>/dev/null || true)"
    if [ -z "$owner_pid" ] || [ "$owner_pid" = "$$" ]; then
      rm -f "$RELOAD_LOCK_OWNER_FILE"
      rmdir "$RELOAD_LOCK_DIR" >/dev/null 2>&1 || true
    fi
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

reload_lock_owner_alive() {
  local owner_pid
  owner_pid="$(cat "$RELOAD_LOCK_OWNER_FILE" 2>/dev/null || true)"
  case "$owner_pid" in
    ""|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$owner_pid" >/dev/null 2>&1
}

remove_stale_reload_lock() {
  reload_lock_owner_alive && return 1
  rm -f "$RELOAD_LOCK_OWNER_FILE"
  rmdir "$RELOAD_LOCK_DIR" >/dev/null 2>&1
}

acquire_reload_lock() {
  local deadline now age
  deadline=$(( $(date +%s) + RELOAD_LOCK_WAIT_SECONDS ))

  while ! mkdir "$RELOAD_LOCK_DIR" 2>/dev/null; do
    WAITED_FOR_LOCK=1
    age=$(reload_lock_age)
    if [ "$age" -gt "$RELOAD_LOCK_STALE_SECONDS" ] && remove_stale_reload_lock; then
      continue
    fi
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      return 1
    fi
    sleep 0.1 || true
  done

  LOCK_HELD=1
  if ! printf '%s\n' "$$" > "$RELOAD_LOCK_OWNER_FILE"; then
    release_reload_lock
    return 1
  fi
  return 0
}

wait_for_recent_reload() {
  [ "$WAITED_FOR_LOCK" -eq 1 ] || return 1
  wait_for_item "$CORE_ITEM"
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
  local attempts="${2:-$CORE_ITEM_WAIT_ATTEMPTS}"

  while [ "$attempts" -gt 0 ]; do
    if item_loaded "$item_name"; then
      return 0
    fi
    sleep 1 || true
    attempts=$((attempts - 1))
  done

  item_loaded "$item_name"
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

finish_reload() {
  if ! ensure_live_config; then
    echo "SketchyBar restarted, but core item '$CORE_ITEM' did not load." >&2
    return 1
  fi
  if ! wait_for_item space.1 4; then
    local refresh_script="${CONFIG_DIR}/plugins/refresh_spaces.sh"
    [ -f "$refresh_script" ] && env CONFIG_DIR="$CONFIG_DIR" BARISTA_CONFIG_DIR="$CONFIG_DIR" "$refresh_script" >/dev/null 2>&1 || true
    wait_for_item space.1 3 || true
  fi
  return 0
}

if [[ -x "$HELPER" ]]; then
  "$HELPER" restart "$AGENT"
  finish_reload
  exit $?
fi

if launchctl kickstart -k "$LABEL" >/dev/null 2>&1; then
  finish_reload
  exit $?
fi

# Fallback to unload/load if kickstart failed (e.g., label missing)
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" >/dev/null 2>&1 || true
  launchctl load "$PLIST"
  finish_reload
else
  echo "LaunchAgent plist not found: $PLIST" >&2
  exit 1
fi
