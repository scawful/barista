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
  - runtime backend and TUI fallback readiness
  - resolved fonts for icon/text/number families
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
RUNTIME_BACKEND="auto"
if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  WINDOW_MANAGER_MODE="$(jq -r '.modes.window_manager // "auto"' "$STATE_FILE" 2>/dev/null || echo auto)"
  RUNTIME_BACKEND="$(jq -r '.modes.runtime_backend // "auto"' "$STATE_FILE" 2>/dev/null || echo auto)"
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

check_fonts() {
  local font_script="$CONFIG_DIR/scripts/barista-fonts.sh"
  if [ ! -x "$font_script" ]; then
    log_warn "Font resolver missing: $font_script"
    return
  fi

  local report
  report="$("$font_script" --state "$STATE_FILE" --report 2>/dev/null || true)"
  local selected_icon selected_text selected_numbers
  local source_icon source_text source_numbers
  local installed_icon installed_text installed_numbers

  selected_icon="$(printf '%s\n' "$report" | awk -F= '/^font.report.selected.icon=/{print substr($0, index($0, "=") + 1); exit}')"
  selected_text="$(printf '%s\n' "$report" | awk -F= '/^font.report.selected.text=/{print substr($0, index($0, "=") + 1); exit}')"
  selected_numbers="$(printf '%s\n' "$report" | awk -F= '/^font.report.selected.numbers=/{print substr($0, index($0, "=") + 1); exit}')"
  source_icon="$(printf '%s\n' "$report" | awk -F= '/^font.report.source.icon=/{print $2; exit}')"
  source_text="$(printf '%s\n' "$report" | awk -F= '/^font.report.source.text=/{print $2; exit}')"
  source_numbers="$(printf '%s\n' "$report" | awk -F= '/^font.report.source.numbers=/{print $2; exit}')"
  installed_icon="$(printf '%s\n' "$report" | awk -F= '/^font.report.installed.icon=/{print $2; exit}')"
  installed_text="$(printf '%s\n' "$report" | awk -F= '/^font.report.installed.text=/{print $2; exit}')"
  installed_numbers="$(printf '%s\n' "$report" | awk -F= '/^font.report.installed.numbers=/{print $2; exit}')"

  if [ "$installed_icon" = "1" ]; then
    log_ok "Icon font ready: ${selected_icon:-unknown} (${source_icon})"
  else
    log_warn "Icon font unresolved; preferred family missing"
  fi
  if [ "$installed_text" = "1" ]; then
    log_ok "Text font ready: ${selected_text:-unknown} (${source_text})"
  else
    log_warn "Text font unresolved; preferred family missing"
  fi
  if [ "$installed_numbers" = "1" ]; then
    log_ok "Number font ready: ${selected_numbers:-unknown} (${source_numbers})"
  else
    log_warn "Number font unresolved; preferred family missing"
  fi

  if { [ "$installed_icon" != "1" ] || [ "$installed_text" != "1" ] || [ "$installed_numbers" != "1" ]; } \
      && [ "$FIX" -eq 1 ] && [ -x "$CONFIG_DIR/scripts/setup_machine.sh" ]; then
    if "$CONFIG_DIR/scripts/setup_machine.sh" --fonts-only --yes --no-reload >/dev/null 2>&1; then
      log_ok "Fonts install attempted via setup_machine.sh"
    else
      log_warn "Could not auto-install fonts"
    fi
  fi
}

check_runtime_backend() {
  case "$RUNTIME_BACKEND" in
    lua)
      log_ok "Runtime backend pinned to Lua-only mode"
      if [ -x "$CONFIG_DIR/bin/barista" ]; then
        log_ok "TUI available for Lua-only debugging"
      else
        log_warn "Lua-only runtime selected but bin/barista is missing"
      fi
      if [ -x "$CONFIG_DIR/scripts/install-tui.sh" ]; then
        if "$CONFIG_DIR/scripts/install-tui.sh" --check >/dev/null 2>&1; then
          log_ok "TUI Python dependencies are installed"
        else
          log_warn "TUI Python dependencies missing; run scripts/install-tui.sh --yes"
        fi
      fi
      ;;
    auto|"")
      log_ok "Runtime backend uses auto helper detection"
      ;;
    *)
      log_warn "Unknown runtime backend in state.json: $RUNTIME_BACKEND"
      ;;
  esac
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
check_runtime_backend
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
  printf 'doctor.report.runtime_backend=%s\n' "$RUNTIME_BACKEND"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
