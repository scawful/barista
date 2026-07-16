#!/bin/bash
# set_mode.sh - Switch Barista profiles or WM modes
# Usage: ./set_mode.sh [profile_name] [wm_mode]

set -e

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${HOME}/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-${CONFIG_DIR}/state.json}"
NO_RELOAD="${BARISTA_NO_RELOAD:-0}"

if [ ! -f "$STATE_FILE" ]; then
  echo "Error: State file not found at $STATE_FILE"
  exit 1
fi

PROFILE=${1:-}
WM_MODE=${2:-}

if [ -z "$PROFILE" ]; then
  echo "Current State:"
  cat "$STATE_FILE"
  echo ""
  echo "Usage: $0 <profile> [wm_mode]"
  echo "Profiles: minimal, cozy, personal, work"
  echo "WM Modes: auto, disabled, required"
  exit 0
fi

# Update Profile
if [ -n "$PROFILE" ]; then
  # check if profile exists
  if [ ! -f "$CONFIG_DIR/profiles/$PROFILE.lua" ]; then
    echo "Warning: Profile '$PROFILE' not found in $CONFIG_DIR/profiles/"
  fi
  
  # Profile switching is intentionally reversible: preserve explicit local
  # overrides. Use setup_machine.sh --profile-variant work when a privacy
  # boundary should clear personal task and integration state.
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
    # Disable yabai shortcuts in disabled mode.
    tmp2=$(mktemp)
    jq '.toggles.yabai_shortcuts = false' "$STATE_FILE" > "$tmp2" && mv "$tmp2" "$STATE_FILE"
  fi
fi

if [ -x "$CONFIG_DIR/scripts/setup_machine.sh" ]; then
  if [ "$NO_RELOAD" = "1" ]; then
    BARISTA_RELOAD_SKHD=0 "$CONFIG_DIR/scripts/setup_machine.sh" \
      --state "$STATE_FILE" --refresh-shortcuts-only --yes --no-reload >/dev/null
  else
    "$CONFIG_DIR/scripts/setup_machine.sh" \
      --state "$STATE_FILE" --refresh-shortcuts-only --yes --no-reload >/dev/null
  fi
fi

if [ "$NO_RELOAD" != "1" ]; then
  echo "Reloading SketchyBar..."
  if [ -x "$CONFIG_DIR/plugins/reload_sketchybar.sh" ]; then
    "$CONFIG_DIR/plugins/reload_sketchybar.sh"
  else
    sketchybar --reload
  fi
fi
