#!/bin/bash
# App names are data arguments, never interpolated into AppleScript source.
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
ACTION="${1:-}"
APP_NAME="${2:-}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-$(command -v osascript 2>/dev/null || true)}"
YABAI_BIN="${BARISTA_YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"

case "$ACTION" in
  show|hide|quit|force-quit|force_quit) ;;
  *) echo "Usage: $0 <show|hide|quit|force-quit> [app name]" >&2; exit 1 ;;
esac

if [ -z "$APP_NAME" ]; then
  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    APP_NAME="$("$YABAI_BIN" -m query --windows --window 2>/dev/null | "$JQ_BIN" -r '.app // empty' 2>/dev/null)"
  fi
  if [ -z "$APP_NAME" ] && [ -n "$OSASCRIPT_BIN" ]; then
    APP_NAME="$("$OSASCRIPT_BIN" -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)"
  fi
fi
[ -n "$APP_NAME" ] || { echo 'App unavailable. Reopen the menu.' >&2; exit 1; }

case "$ACTION" in
  force-quit|force_quit)
    # pkill uses a regular expression even with -x; escape the exact app name.
    process_pattern="$(printf '%s' "$APP_NAME" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
    pkill -x -- "$process_pattern"
    ;;
  *)
    [ -n "$OSASCRIPT_BIN" ] || { echo 'osascript is unavailable.' >&2; exit 1; }
    "$OSASCRIPT_BIN" - "$ACTION" "$APP_NAME" <<'APPLESCRIPT'
on run argv
  set requestedAction to item 1 of argv
  set appName to item 2 of argv
  if requestedAction is "show" then
    tell application appName to activate
  else if requestedAction is "hide" then
    tell application "System Events" to set visible of application process appName to false
  else if requestedAction is "quit" then
    tell application appName to quit
  end if
end run
APPLESCRIPT
    ;;
esac
