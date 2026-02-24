#!/bin/bash

# Barista Plugin: AI Resource Toggle
# Integration for High Performance AI mode

SCRIPTS_DIR="$HOME/src/lab/scripts"
RESOURCE_MANAGER="$SCRIPTS_DIR/ai_resource_manager.sh"

GREEN="0xffa6e3a1"
RED="0xfff38ba8"
ICON_ON="󰓅"
ICON_OFF="󰾆"

if [ "$SENDER" = "mouse.clicked" ]; then
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
