#!/bin/bash
# Barista supervisor script for SketchyBar, Yabai, and skhd.
# The installer renders the active runtime path into the LaunchAgent.

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}}"
HELPER="${BARISTA_AGENT_HELPER:-$CONFIG_DIR/helpers/launch_agent_manager.sh}"
DOMAIN="gui/$(id -u)"
# Default to the current yabai label when installed, but keep the legacy label as fallback.
SKETCHYBAR_LABEL="${BARISTA_SKETCHYBAR_LABEL:-homebrew.mxcl.sketchybar}"
if [[ -n "${BARISTA_YABAI_LABEL:-}" ]]; then
  YABAI_LABEL="$BARISTA_YABAI_LABEL"
elif [[ -f "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist" ]]; then
  YABAI_LABEL="com.asmvik.yabai"
else
  YABAI_LABEL="com.koekeishiya.yabai"
fi
SKHD_LABEL="${BARISTA_SKHD_LABEL:-com.koekeishiya.skhd}"
AGENTS=("$YABAI_LABEL" "$SKHD_LABEL" "$SKETCHYBAR_LABEL")

if [ -z "${HOMEBREW_PREFIX:-}" ] && command -v brew >/dev/null 2>&1; then
  HOMEBREW_PREFIX="$(brew --prefix)"
fi
if [ -z "${HOMEBREW_PREFIX:-}" ]; then
  if [ "$(uname -m)" = "arm64" ]; then
    HOMEBREW_PREFIX="/opt/homebrew"
  else
    HOMEBREW_PREFIX="/usr/local"
  fi
fi
DEFAULT_PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
PYTHON_PATH=""
if [ -d "${HOMEBREW_PREFIX}/opt/python@3.14/bin" ]; then
  PYTHON_PATH="${HOMEBREW_PREFIX}/opt/python@3.14/bin"
fi
if [ -n "$PYTHON_PATH" ]; then
  DEFAULT_PATH="${PYTHON_PATH}:${DEFAULT_PATH}"
fi

if [ -n "${BARISTA_PATH:-}" ]; then
  export PATH="$BARISTA_PATH"
elif [ -n "${PATH:-}" ]; then
  export PATH="${PATH}:${DEFAULT_PATH}"
else
  export PATH="$DEFAULT_PATH"
fi
export BARISTA_CONFIG_DIR="$CONFIG_DIR"

# Keep runtime settings local to this supervisor. Global launchctl setenv
# leaks Barista paths into unrelated applications and isolated test processes.

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
      if launchctl print "${DOMAIN}/${label}" >/dev/null 2>&1; then
        if [[ "$action" == "restart" ]]; then
          launchctl kickstart -kp "${DOMAIN}/${label}"
        else
          launchctl kickstart -p "${DOMAIN}/${label}"
        fi
      elif plist=$(fallback_plist "$label"); then
        launchctl bootstrap "$DOMAIN" "$plist"
      else
        echo "Missing LaunchAgent: $label" >&2
        return 1
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

if [[ "$command" == "start" || "$command" == "restart" ]]; then
  # Read preferences without rewriting state or silently treating corrupt state
  # as permission to start window-management services.
  preferences="$(python3 - "$CONFIG_DIR/state.json" <<'PYSTATE'
import json, sys

# Same aliases as binary_resolver.normalize_window_manager_mode.
ALIASES = {
    "": "auto", "auto": "auto",
    "off": "disabled", "false": "disabled", "none": "disabled", "disable": "disabled", "disabled": "disabled",
    "opt": "optional", "optional": "optional",
    "on": "required", "enable": "required", "enabled": "required", "require": "required", "required": "required",
}
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        state = json.load(handle)
except FileNotFoundError:
    state = {}
if not isinstance(state, dict):
    raise ValueError("state must be an object")
modes = state.get("modes") or {}
toggles = state.get("toggles") or {}
mode = ALIASES.get(str(modes.get("window_manager") or "auto").lower())
if mode is None:
    raise ValueError("invalid window manager mode")
shortcuts = toggles.get("yabai_shortcuts", True)
if not isinstance(shortcuts, bool):
    raise ValueError("yabai_shortcuts must be a boolean")
print(mode, "on" if shortcuts else "off")
PYSTATE
)"
  read -r wm_mode shortcuts_enabled <<< "$preferences"
  AGENTS=()
  if [[ "$wm_mode" == "required" || "$wm_mode" == "auto" ]]; then
    if [[ "$wm_mode" == "required" ]] || fallback_plist "$YABAI_LABEL" >/dev/null; then
      AGENTS+=("$YABAI_LABEL")
    fi
  fi
  if [[ "$wm_mode" != "disabled" && "$shortcuts_enabled" == "on" ]]; then
    if [[ "$wm_mode" == "required" ]] || fallback_plist "$SKHD_LABEL" >/dev/null; then
      AGENTS+=("$SKHD_LABEL")
    fi
  fi
  AGENTS+=("$SKETCHYBAR_LABEL")
fi

# SketchyBar starts last, so an optional service's failure must not stop it.
start_label() {
  local action="$1" label="$2"
  if [[ "$label" == "$SKETCHYBAR_LABEL" || "$wm_mode" == "required" ]]; then
    manage_label "$action" "$label"
  else
    manage_label "$action" "$label" || log "Skipped ${label}: ${action} failed"
  fi
}

case "$command" in
  start)
    for label in "${AGENTS[@]}"; do
      log "Starting ${label}"
      start_label start "$label"
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
      start_label restart "$label"
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
