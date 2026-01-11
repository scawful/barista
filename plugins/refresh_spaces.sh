#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
SCRIPTS_DIR="${SCRIPTS_DIR:-${BARISTA_SCRIPTS_DIR:-}}"

expand_path() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

if [ -z "$SCRIPTS_DIR" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  SCRIPTS_DIR=$(jq -r '.paths.scripts_dir // .paths.scripts // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ "$SCRIPTS_DIR" = "null" ]; then
    SCRIPTS_DIR=""
  fi
fi

if [ -n "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$(expand_path "$SCRIPTS_DIR")"
fi

if [ -z "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$CONFIG_DIR/scripts"
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$HOME/.config/scripts"
fi
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
  bar_height="${1:-}"
  if [ -z "$bar_height" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
    bar_height=$(jq -r '.appearance.bar_height // empty' "$STATE_FILE" 2>/dev/null || true)
  fi
  if [ -z "$bar_height" ] || [ "$bar_height" = "null" ]; then
    bar_height=28
  fi
  "$SCRIPTS_DIR/update_external_bar.sh" "$bar_height"
fi
