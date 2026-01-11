#!/usr/bin/env bash
# Ensure the Homebrew SketchyBar LaunchAgent uses the Barista wrapper.

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
WRAPPER_PATH="${SKETCHYBAR_WRAPPER:-$CONFIG_DIR/bin/sketchybar_wrapper.sh}"
PLIST_PATH="${SKETCHYBAR_PLIST:-$HOME/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist}"
LABEL="${SKETCHYBAR_LABEL:-homebrew.mxcl.sketchybar}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
DOMAIN="gui/$(id -u)"
RESTART=1
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: fix_sketchybar_agent.sh [options]

Ensures the Homebrew SketchyBar LaunchAgent points to the Barista wrapper.
Run this after brew updates or if the agent reverts to the stock binary.

Options:
  --no-restart   Update plist without reloading the agent
  --dry-run      Show what would change without writing
  --plist <path> Override plist path
  --wrapper <path> Override wrapper path
  --label <label> Override launchctl label
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-restart)
      RESTART=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --plist)
      PLIST_PATH="$2"
      shift 2
      ;;
    --wrapper)
      WRAPPER_PATH="$2"
      shift 2
      ;;
    --label)
      LABEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "LaunchAgent not found: $PLIST_PATH" >&2
  echo "Run: brew services start sketchybar" >&2
  exit 1
fi

if [[ ! -x "$WRAPPER_PATH" ]]; then
  echo "Wrapper not executable: $WRAPPER_PATH" >&2
  echo "Run: ./scripts/deploy.sh" >&2
  exit 1
fi

current="$($PLIST_BUDDY -c 'Print :ProgramArguments:0' "$PLIST_PATH" 2>/dev/null || true)"

if [[ "$current" != "$WRAPPER_PATH" ]]; then
  echo "Updating ProgramArguments to use wrapper: $WRAPPER_PATH"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Would rewrite ProgramArguments in $PLIST_PATH"
  else
    $PLIST_BUDDY -c 'Delete :ProgramArguments' "$PLIST_PATH" 2>/dev/null || true
    $PLIST_BUDDY -c 'Add :ProgramArguments array' "$PLIST_PATH"
    $PLIST_BUDDY -c "Add :ProgramArguments:0 string $WRAPPER_PATH" "$PLIST_PATH"
  fi
else
  echo "ProgramArguments already set to wrapper."
fi

if [[ $RESTART -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Would reload launch agent: $LABEL"
  else
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
    launchctl kickstart -k "$DOMAIN/$LABEL" 2>/dev/null || true
    echo "Reloaded launch agent: $LABEL"
  fi
else
  echo "Skipping launch agent reload (--no-restart)."
fi
