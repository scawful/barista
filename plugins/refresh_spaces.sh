#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

CACHE_FILE="${CONFIG_DIR}/.spaces_cache"
ACTIVE_CACHE_FILE="${CONFIG_DIR}/.spaces_active_cache"
LOCK_DIR="${CONFIG_DIR}/.refresh_spaces.lock"
ICON_CACHE_DIR="${CONFIG_DIR}/cache/space_icons"

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
current_active_state=""
if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  current_display_state="$(yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(\",\")' 2>/dev/null || true)"
  # Track spaces by display/index to catch moves between monitors
  current_space_state="$(yabai -m query --spaces 2>/dev/null | jq -r '[.[] | "\(.display)-\(.index)"] | sort | join(\",\")' 2>/dev/null || true)"
  # Track visible/focused space mapping per display to avoid full rebuild on focus/display changes
  current_active_state="$(yabai -m query --spaces 2>/dev/null | jq -r '[.[] | select(."is-visible" == true) | "\(.display):\(.index)"] | sort | join(\",\")' 2>/dev/null || true)"
fi

if [ -n "$current_display_state$current_space_state" ]; then
  combined_state="${current_display_state}|${current_space_state}"
  cached_state="$(cat "$CACHE_FILE" 2>/dev/null || true)"
  if [ "$combined_state" = "$cached_state" ]; then
    cached_active_state="$(cat "$ACTIVE_CACHE_FILE" 2>/dev/null || true)"
    if [ -n "$current_active_state" ] && [ "$current_active_state" != "$cached_active_state" ]; then
      printf '%s' "$current_active_state" >"$ACTIVE_CACHE_FILE" || true
      sketchybar --trigger space_change >/dev/null 2>&1 || true
      sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  cached_space_state=""
  case "$cached_state" in
    *"|"*) cached_space_state="${cached_state#*|}" ;;
  esac
  if [ -n "$cached_space_state" ] && [ "$cached_space_state" != "$current_space_state" ]; then
    if [ -d "$ICON_CACHE_DIR" ]; then
      rm -f "$ICON_CACHE_DIR"/* 2>/dev/null || true
    fi
  fi
  printf '%s' "$combined_state" >"$CACHE_FILE" || true
  printf '%s' "$current_active_state" >"$ACTIVE_CACHE_FILE" || true
fi

# OPTIMIZED: Removed sleep - the cache check above provides sufficient debouncing

"$CONFIG_DIR/plugins/simple_spaces.sh"

if [ -x "$SCRIPTS_DIR/update_external_bar.sh" ]; then
  bar_height="${1:-}"
  if [ -z "$bar_height" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
    bar_height=$(jq -r '.appearance.bar_height // empty' "$STATE_FILE" 2>/dev/null || true)
  fi
  if [ -z "$bar_height" ] || [ "$bar_height" = "null" ]; then
    bar_height=28
  fi
  "$SCRIPTS_DIR/update_external_bar.sh" "$bar_height"
fi
