#!/bin/bash

# Barista Plugin: AI Resource Toggle
# Integration for High Performance AI mode

RESOURCE_MANAGER="${BARISTA_AI_RESOURCE_MANAGER:-}"
if [ -z "$RESOURCE_MANAGER" ] && command -v ai_resource_manager.sh >/dev/null 2>&1; then
    RESOURCE_MANAGER="$(command -v ai_resource_manager.sh)"
fi

GREEN="0xffa6e3a1"
RED="0xfff38ba8"
ICON_ON="󰓅"
ICON_OFF="󰾆"

if [ "$SENDER" = "mouse.clicked" ]; then
    if [ -z "$RESOURCE_MANAGER" ] || [ ! -x "$RESOURCE_MANAGER" ]; then
        sketchybar --set "$NAME" label="AI helper unavailable"
        exit 0
    fi
    if [ -f "/tmp/ai_resource_quarantine.list" ]; then
        "$RESOURCE_MANAGER" off
    else
        "$RESOURCE_MANAGER" on
    fi
    sketchybar --trigger ai_resource_update
fi

if [ -f "/tmp/ai_resource_quarantine.list" ]; then
    sketchybar --set "$NAME" icon="$ICON_ON" icon.color="$RED" label="AI: HIGH"
else
    sketchybar --set "$NAME" icon="$ICON_OFF" icon.color="$GREEN" label="AI: NORM"
fi
