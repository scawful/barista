#!/bin/sh

USER_LOAD=${user_load:-0}
SYS_LOAD=${sys_load:-0}
TOTAL_LOAD=${total_load:-0}

LABEL="CPU ${TOTAL_LOAD}%"

if [ "$USER_LOAD" -gt 0 ] || [ "$SYS_LOAD" -gt 0 ]; then
  LABEL="CPU ${TOTAL_LOAD}% (U:${USER_LOAD}% S:${SYS_LOAD}%)"
fi

sketchybar --set "$NAME" label="$LABEL"
