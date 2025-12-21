#!/bin/bash
# Barista supervisor script for SketchyBar, Yabai, and skhd.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
HELPER="${BARISTA_AGENT_HELPER:-$CONFIG_DIR/helpers/launch_agent_manager.sh}"
DOMAIN="gui/$(id -u)"
# Default to Koekeishiya labels used by current installs; override via env if needed.
SKETCHYBAR_LABEL="${BARISTA_SKETCHYBAR_LABEL:-homebrew.mxcl.sketchybar}"
YABAI_LABEL="${BARISTA_YABAI_LABEL:-com.koekeishiya.yabai}"
SKHD_LABEL="${BARISTA_SKHD_LABEL:-com.koekeishiya.skhd}"
AGENTS=("$SKETCHYBAR_LABEL" "$YABAI_LABEL" "$SKHD_LABEL")

HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
DEFAULT_PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
PYTHON_PATH=""
if [ -d "${HOMEBREW_PREFIX}/opt/python@3.14/bin" ]; then
  PYTHON_PATH="${HOMEBREW_PREFIX}/opt/python@3.14/bin"
fi
if [ -n "$PYTHON_PATH" ]; then
  DEFAULT_PATH="${PYTHON_PATH}:${DEFAULT_PATH}"
fi

export PATH="${BARISTA_PATH:-$DEFAULT_PATH}"

if command -v launchctl >/dev/null 2>&1; then
  launchctl setenv PATH "$PATH" >/dev/null 2>&1 || true
fi

log() {
  printf '[barista-agent] %s\n' "$*"
}

fallback_plist() {
  local label="$1"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"
  if [[ -f "$plist" ]]; then
    printf '%s\n' "$plist"
    return 0
  fi
  return 1
}

manage_label() {
  local action="$1"
  local label="$2"

  if [[ -x "$HELPER" ]]; then
    "$HELPER" "$action" "$label"
    return
  fi

  case "$action" in
    start|restart)
      if ! launchctl kickstart -kp "${DOMAIN}/${label}" >/dev/null 2>&1; then
        if plist=$(fallback_plist "$label"); then
          launchctl bootstrap "$DOMAIN" "$plist"
        else
          launchctl bootstrap "$DOMAIN" "$HOME/Library/LaunchAgents/${label}.plist" 2>/dev/null || true
        fi
      fi
      ;;
    stop)
      launchctl bootout "${DOMAIN}/${label}" >/dev/null 2>&1 || true
      ;;
    status)
      launchctl print "${DOMAIN}/${label}"
      ;;
  esac
}

command="${1:-start}"

case "$command" in
  start)
    for label in "${AGENTS[@]}"; do
      log "Starting ${label}"
      manage_label start "$label"
    done
    ;;
  stop)
    for label in "${AGENTS[@]}"; do
      log "Stopping ${label}"
      manage_label stop "$label"
    done
    ;;
  restart)
    for label in "${AGENTS[@]}"; do
      log "Restarting ${label}"
      manage_label restart "$label"
    done
    ;;
  status)
    for label in "${AGENTS[@]}"; do
      log "Status for ${label}"
      manage_label status "$label"
    done
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
