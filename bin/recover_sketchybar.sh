#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
CONFIG_FILE="${SKETCHYBAR_CONFIG:-$CONFIG_DIR/sketchybarrc}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"
LABEL="${SKETCHYBAR_LABEL:-homebrew.mxcl.sketchybar}"
DOMAIN="gui/$(id -u)"
PLIST_PATH="${SKETCHYBAR_PLIST:-$HOME/Library/LaunchAgents/${LABEL}.plist}"

if [[ ! -x "$SKETCHYBAR_BIN" ]]; then
  SKETCHYBAR_BIN="$(command -v sketchybar || true)"
fi

if [[ -z "$SKETCHYBAR_BIN" || ! -x "$SKETCHYBAR_BIN" ]]; then
  echo "sketchybar not found" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "sketchybarrc not found: $CONFIG_FILE" >&2
  exit 1
fi

CORE_ITEM="${BARISTA_CORE_ITEM:-front_app}"

item_loaded() {
  local item_name="${1:-}"
  [[ -n "$item_name" ]] || return 1

  local output
  output="$("$SKETCHYBAR_BIN" --query "$item_name" 2>/dev/null || true)"
  [[ -n "$output" ]]
}

wait_for_item() {
  local item_name="${1:-$CORE_ITEM}"
  local attempts="${2:-5}"

  while (( attempts > 0 )); do
    if item_loaded "$item_name"; then
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done

  return 1
}

reload_live_config() {
  "$SKETCHYBAR_BIN" --reload >/dev/null 2>&1 || true
  wait_for_item "$CORE_ITEM" 5
}

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl unsetenv BARISTA_STARTUP_TRACE 2>/dev/null || true
launchctl unsetenv BARISTA_LAUNCHD_REQUIRE_DELAY 2>/dev/null || true
pkill -f '(^| )sketchybar($| )' 2>/dev/null || true

if [[ -f "$PLIST_PATH" ]]; then
  launchctl bootstrap "$DOMAIN" "$PLIST_PATH" 2>/dev/null || true
  launchctl kickstart -k "$DOMAIN/$LABEL" 2>/dev/null || true

  if wait_for_item "$CORE_ITEM" 5 || reload_live_config; then
    echo "SketchyBar recovered via LaunchAgent."
    exit 0
  fi
fi

nohup "$SKETCHYBAR_BIN" --config "$CONFIG_FILE" \
  >/tmp/barista_manual_recover.out 2>/tmp/barista_manual_recover.err </dev/null &

if wait_for_item "$CORE_ITEM" 5 || reload_live_config; then
  echo "SketchyBar recovered with direct config launch."
  exit 0
fi

if pgrep -f "^$SKETCHYBAR_BIN --config $CONFIG_FILE$" >/dev/null 2>&1; then
  echo "SketchyBar relaunched. Give it a moment to repopulate."
  exit 0
fi

echo "SketchyBar did not relaunch. Check /tmp/barista_manual_recover.err." >&2
exit 1
