#!/bin/bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/.config/scripts}"
CACHE_FILE="${CONFIG_DIR}/.spaces_cache"
LOCK_DIR="${CONFIG_DIR}/.refresh_spaces.lock"

# Simple lock to avoid overlapping refreshes from rapid display events
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
cleanup_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup_lock EXIT

# Skip work if display topology hasn't changed (debounce display events)
current_display_state=""
if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  current_display_state="$(yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(",")' 2>/dev/null || true)"
fi

if [ -n "$current_display_state" ]; then
  cached_state="$(cat "$CACHE_FILE" 2>/dev/null || true)"
  if [ "$current_display_state" = "$cached_state" ]; then
    exit 0
  fi
  printf '%s' "$current_display_state" >"$CACHE_FILE" || true
fi

# Race condition mitigation: Wait briefly for main bar items (anchors) to be registered
sleep 0.1

"$CONFIG_DIR/plugins/simple_spaces.sh"

if [ -x "$SCRIPTS_DIR/update_external_bar.sh" ]; then
  "$SCRIPTS_DIR/update_external_bar.sh" "${1:-}"
fi
