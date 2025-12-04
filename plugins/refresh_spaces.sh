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

# Skip work if neither display topology nor space mapping changed
current_display_state=""
current_space_state=""
if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  current_display_state="$(yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(\",\")' 2>/dev/null || true)"
  # Track spaces by display/index to catch moves between monitors
  current_space_state="$(yabai -m query --spaces 2>/dev/null | jq -r '[.[] | "\(.display)-\(.index)"] | sort | join(\",\")' 2>/dev/null || true)"
fi

if [ -n "$current_display_state$current_space_state" ]; then
  combined_state="${current_display_state}|${current_space_state}"
  cached_state="$(cat "$CACHE_FILE" 2>/dev/null || true)"
  if [ "$combined_state" = "$cached_state" ]; then
    exit 0
  fi
  printf '%s' "$combined_state" >"$CACHE_FILE" || true
fi

# OPTIMIZED: Removed sleep - the cache check above provides sufficient debouncing

"$CONFIG_DIR/plugins/simple_spaces.sh"

if [ -x "$SCRIPTS_DIR/update_external_bar.sh" ]; then
  "$SCRIPTS_DIR/update_external_bar.sh" "${1:-}"
fi
