#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"

FIX=0
REPORT=0

FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0

usage() {
  cat <<EOF
Usage: $0 [--fix] [--report] [--config-dir <path>] [--state <path>]

Checks:
  - sketchybar/yabai/skhd availability and running status
  - required fonts
  - launch agent presence/loading
  - wrapper paths
  - script executable permissions
EOF
}

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    ~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

log_ok() {
  OK_COUNT=$((OK_COUNT + 1))
  printf '[ok] %s\n' "$*"
}

log_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[warn] %s\n' "$*" >&2
}

log_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[fail] %s\n' "$*" >&2
}

maybe_fix() {
  local desc="$1"
  shift
  if [ "$FIX" -ne 1 ]; then
    return 1
  fi
  printf '[fix] %s\n' "$desc"
  "$@" >/dev/null 2>&1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fix)
      FIX=1
      shift
      ;;
    --report)
      REPORT=1
      shift
      ;;
    --config-dir)
      CONFIG_DIR="${2:-}"
      shift 2
      ;;
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

CONFIG_DIR="$(expand_home "$CONFIG_DIR")"
STATE_FILE="$(expand_home "$STATE_FILE")"

WINDOW_MANAGER_MODE="auto"
if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  WINDOW_MANAGER_MODE="$(jq -r '.modes.window_manager // "auto"' "$STATE_FILE" 2>/dev/null || echo auto)"
fi

check_binary() {
  local cmd="$1"
  local required="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "$cmd is installed"
    return 0
  fi
  if [ "$required" = "required" ]; then
    log_fail "$cmd is not installed"
  else
    log_warn "$cmd is not installed"
  fi
  return 1
}

check_process() {
  local proc="$1"
  local required="$2"
  if pgrep -x "$proc" >/dev/null 2>&1; then
    log_ok "$proc is running"
    return 0
  fi

  if [ "$required" = "required" ]; then
    log_warn "$proc is not running"
  else
    log_warn "$proc is not running (optional)"
  fi

  if [ "$FIX" -eq 1 ]; then
    local launched=0
    if [ -x "$CONFIG_DIR/launch_agents/barista-launch.sh" ]; then
      if "$CONFIG_DIR/launch_agents/barista-launch.sh" restart >/dev/null 2>&1; then
        launched=1
      fi
    fi
    if [ "$launched" -eq 0 ] && command -v brew >/dev/null 2>&1; then
      brew services start "$proc" >/dev/null 2>&1 || true
    fi
    if pgrep -x "$proc" >/dev/null 2>&1; then
      log_ok "$proc started successfully"
      return 0
    fi
  fi

  if [ "$required" = "required" ]; then
    log_fail "$proc is still not running"
  fi
}

font_installed() {
  local pattern="$1"
  local p
  for p in "$HOME/Library/Fonts" "/Library/Fonts" "/System/Library/Fonts"; do
    [ -d "$p" ] || continue
    if find "$p" -maxdepth 1 -iname "*$pattern*" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done
  return 1
}

check_fonts() {
  local missing=0
  if font_installed "Hack Nerd Font"; then
    log_ok "Hack Nerd Font detected"
  else
    log_warn "Hack Nerd Font missing"
    missing=1
  fi

  if font_installed "SourceCodePro" || font_installed "Source Code Pro"; then
    log_ok "Source Code Pro detected"
  else
    log_warn "Source Code Pro missing"
    missing=1
  fi

  if [ "$missing" -eq 1 ] && [ "$FIX" -eq 1 ] && [ -x "$CONFIG_DIR/scripts/setup_machine.sh" ]; then
    if "$CONFIG_DIR/scripts/setup_machine.sh" --fonts-only --yes --no-reload >/dev/null 2>&1; then
      log_ok "Fonts install attempted via setup_machine.sh"
    else
      log_warn "Could not auto-install fonts"
    fi
  fi
}

check_launch_agent() {
  local domain label plist
  domain="gui/$(id -u)"
  label="dev.barista.control"
  plist="$HOME/Library/LaunchAgents/${label}.plist"

  if [ -f "$plist" ]; then
    log_ok "LaunchAgent plist present: $plist"
  else
    log_warn "LaunchAgent plist missing: $plist"
    return
  fi

  if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
    log_ok "LaunchAgent loaded: ${domain}/${label}"
  else
    log_warn "LaunchAgent not loaded: ${domain}/${label}"
    if [ "$FIX" -eq 1 ]; then
      launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
      launchctl kickstart -kp "${domain}/${label}" >/dev/null 2>&1 || true
      if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
        log_ok "LaunchAgent loaded after fix"
      else
        log_warn "LaunchAgent still not loaded"
      fi
    fi
  fi
}

check_wrapper_paths() {
  local sketchy_wrapper yabai_wrapper
  sketchy_wrapper="$CONFIG_DIR/bin/sketchybar_wrapper.sh"
  yabai_wrapper="$HOME/.local/bin/yabai_control_wrapper.sh"

  if [ -x "$sketchy_wrapper" ]; then
    log_ok "SketchyBar wrapper exists: $sketchy_wrapper"
  else
    log_warn "SketchyBar wrapper missing or not executable: $sketchy_wrapper"
  fi

  if [ -x "$yabai_wrapper" ]; then
    log_ok "yabai wrapper exists: $yabai_wrapper"
  else
    log_warn "yabai wrapper missing: $yabai_wrapper"
    if [ "$FIX" -eq 1 ]; then
      mkdir -p "$(dirname "$yabai_wrapper")"
      cat > "$yabai_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
exec "$CONFIG_DIR/scripts/yabai_control.sh" "$@"
EOF
      chmod +x "$yabai_wrapper"
      if [ -x "$yabai_wrapper" ]; then
        log_ok "Created yabai wrapper: $yabai_wrapper"
      else
        log_warn "Failed to create yabai wrapper"
      fi
    fi
  fi
}

check_script_permissions() {
  local script
  local scripts=(
    "$CONFIG_DIR/scripts/setup_machine.sh"
    "$CONFIG_DIR/scripts/update_work_mac.sh"
    "$CONFIG_DIR/scripts/work_mac_sync.sh"
    "$CONFIG_DIR/scripts/space_action.sh"
    "$CONFIG_DIR/scripts/yabai_control.sh"
    "$CONFIG_DIR/scripts/install.sh"
    "$CONFIG_DIR/scripts/install-tui.sh"
  )
  for script in "${scripts[@]}"; do
    if [ ! -e "$script" ]; then
      log_warn "Script missing: $script"
      continue
    fi
    if [ -x "$script" ]; then
      log_ok "Script executable: $script"
      continue
    fi
    log_warn "Script not executable: $script"
    if [ "$FIX" -eq 1 ]; then
      chmod +x "$script" >/dev/null 2>&1 || true
      if [ -x "$script" ]; then
        log_ok "Fixed executable permission: $script"
      else
        log_warn "Could not set executable permission: $script"
      fi
    fi
  done
}

check_state_json() {
  if [ ! -f "$STATE_FILE" ]; then
    log_warn "state.json missing: $STATE_FILE"
    if [ "$FIX" -eq 1 ]; then
      mkdir -p "$(dirname "$STATE_FILE")"
      printf '{}' > "$STATE_FILE"
      log_ok "Created empty state.json"
    fi
    return
  fi
  if command -v jq >/dev/null 2>&1 && jq -e type "$STATE_FILE" >/dev/null 2>&1; then
    log_ok "state.json is valid JSON"
  else
    log_fail "state.json is invalid JSON: $STATE_FILE"
  fi
}

check_skhd_shortcuts() {
  if [ ! -x "$CONFIG_DIR/scripts/yabai_control.sh" ]; then
    log_warn "Cannot run shortcuts doctor; missing yabai_control.sh"
    return
  fi
  if [ "$FIX" -eq 1 ]; then
    if "$CONFIG_DIR/scripts/yabai_control.sh" doctor --fix >/dev/null 2>&1; then
      log_ok "Ran yabai_control.sh doctor --fix"
    else
      log_warn "yabai_control.sh doctor --fix reported issues"
    fi
  else
    if "$CONFIG_DIR/scripts/yabai_control.sh" doctor >/dev/null 2>&1; then
      log_ok "yabai_control.sh doctor passed"
    else
      log_warn "yabai_control.sh doctor reported issues"
    fi
  fi
}

log_ok "barista-doctor start (config=$CONFIG_DIR)"
check_binary sketchybar required
check_binary jq required

case "$WINDOW_MANAGER_MODE" in
  disabled)
    check_binary yabai optional
    check_binary skhd optional
    check_process sketchybar required
    check_process yabai optional
    check_process skhd optional
    ;;
  *)
    check_binary yabai required
    check_binary skhd required
    check_process sketchybar required
    check_process yabai required
    check_process skhd required
    ;;
esac

check_state_json
check_fonts
check_wrapper_paths
check_script_permissions
check_launch_agent
check_skhd_shortcuts

if [ "$REPORT" -eq 1 ]; then
  printf 'doctor.report.status=%s\n' "$( [ "$FAIL_COUNT" -eq 0 ] && printf ok || printf fail )"
  printf 'doctor.report.fail_count=%s\n' "$FAIL_COUNT"
  printf 'doctor.report.warn_count=%s\n' "$WARN_COUNT"
  printf 'doctor.report.ok_count=%s\n' "$OK_COUNT"
  printf 'doctor.report.fix_mode=%s\n' "$FIX"
  printf 'doctor.report.config_dir=%s\n' "$CONFIG_DIR"
  printf 'doctor.report.state_file=%s\n' "$STATE_FILE"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
