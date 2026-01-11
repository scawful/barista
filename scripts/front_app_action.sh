#!/bin/bash
# front_app_action.sh - Control the frontmost application.

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

ACTION="${1:-}"
APP_NAME="${2:-}"

usage() {
  echo "Usage: $0 <show|hide|quit|force-quit> [app name]" >&2
}

if [ -z "$ACTION" ]; then
  usage
  exit 1
fi

if [ -z "$APP_NAME" ]; then
  if command -v yabai >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    APP_NAME=$(yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty' 2>/dev/null)
  fi
  if [ -z "$APP_NAME" ]; then
    APP_NAME=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  fi
fi

if [ -z "$APP_NAME" ]; then
  exit 1
fi

case "$ACTION" in
  show)
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1
    ;;
  hide)
    osascript -e "tell application \"$APP_NAME\" to hide" >/dev/null 2>&1
    ;;
  quit)
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1
    ;;
  force-quit|force_quit)
    if command -v pkill >/dev/null 2>&1; then
      pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    elif command -v killall >/dev/null 2>&1; then
      killall "$APP_NAME" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
