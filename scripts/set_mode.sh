#!/bin/bash
# set_mode.sh - Switch Barista profiles or WM modes
# Usage: ./set_mode.sh [profile_name] [wm_mode]

set -e

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="${CONFIG_DIR}/state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "Error: State file not found at $STATE_FILE"
  exit 1
fi

PROFILE=$1
WM_MODE=$2

if [ -z "$PROFILE" ]; then
  echo "Current State:"
  cat "$STATE_FILE"
  echo ""
  echo "Usage: $0 <profile> [wm_mode]"
  echo "Profiles: minimal, girlfriend, personal, work"
  echo "WM Modes: auto, disabled, required"
  exit 0
fi

# Update Profile
if [ -n "$PROFILE" ]; then
  # check if profile exists
  if [ ! -f "$CONFIG_DIR/profiles/$PROFILE.lua" ]; then
    echo "Warning: Profile '$PROFILE' not found in $CONFIG_DIR/profiles/"
  fi
  
  # Use jq to update
  tmp=$(mktemp)
  jq --arg p "$PROFILE" '.profile = $p' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  echo "Switched to profile: $PROFILE"
fi

# Update WM Mode
if [ -n "$WM_MODE" ]; then
  tmp=$(mktemp)
  jq --arg m "$WM_MODE" '.modes.window_manager = $m' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  echo "Window Manager mode set to: $WM_MODE"
  
  if [ "$WM_MODE" == "disabled" ]; then
    # Disable yabai status too
    tmp2=$(mktemp)
    jq '.widgets.yabai_status = false | .toggles.yabai_shortcuts = false' "$STATE_FILE" > "$tmp2" && mv "$tmp2" "$STATE_FILE"
  fi
fi

echo "Reloading SketchyBar..."
sketchybar --reload
