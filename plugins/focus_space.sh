#!/bin/bash

SPACE_ID="$1"

if [ -z "$SPACE_ID" ]; then
  exit 0
fi

if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
  yabai -m space --focus "$SPACE_ID" >/dev/null 2>&1 || true
else
  case "$SPACE_ID" in
    1) KEY_CODE=18 ;;
    2) KEY_CODE=19 ;;
    3) KEY_CODE=20 ;;
    4) KEY_CODE=21 ;;
    5) KEY_CODE=23 ;;
    6) KEY_CODE=22 ;;
    7) KEY_CODE=26 ;;
    8) KEY_CODE=28 ;;
    9) KEY_CODE=25 ;;
    *) KEY_CODE="" ;;
  esac
  if [ -n "$KEY_CODE" ]; then
    osascript -e "tell application \"System Events\" to key code $KEY_CODE using control down" >/dev/null 2>&1 || open -a "Mission Control"
  else
    open -a "Mission Control"
  fi
fi
