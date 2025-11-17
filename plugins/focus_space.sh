#!/bin/bash

SPACE_ID="$1"

if [ -z "$SPACE_ID" ]; then
  exit 0
fi

if command -v yabai >/dev/null 2>&1 && yabai -m query --spaces >/dev/null 2>&1; then
  yabai -m space --focus "$SPACE_ID" >/dev/null 2>&1 || true
else
  open -a "Mission Control"
fi
