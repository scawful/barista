#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"

FIX=0
REPORT=0
ONBOARD=0
OFFLINE=0

FAIL_COUNT=0
WARN_COUNT=0
OK_COUNT=0
CODE_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
ONBOARD_DEFAULTS=""
ONBOARD_LOCAL=""
ONBOARD_CONFIG_JSON="{}"

usage() {
  cat <<EOF
Usage: $0 [--fix] [--report] [--onboard] [--offline] [--config-dir <path>] [--state <path>]

Checks:
  - sketchybar/yabai/skhd availability and running status
  - runtime backend and TUI fallback readiness
  - resolved fonts for icon/text/number families
  - launch agent presence/loading
  - wrapper paths
  - script executable permissions

With --onboard, also validates portable first-run readiness using
data/onboard.defaults.json plus an optional gitignored
data/onboard.local.json for machine-specific tools.

With --offline (or BARISTA_DOCTOR_OFFLINE=1), skip live process and
LaunchAgent checks so the portable checks can run in CI or dry fixtures.
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
    --onboard)
      ONBOARD=1
      shift
      ;;
    --offline)
      OFFLINE=1
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
CODE_DIR="$(expand_home "$CODE_DIR")"
ONBOARD_DEFAULTS="$CONFIG_DIR/data/onboard.defaults.json"
ONBOARD_LOCAL="$CONFIG_DIR/data/onboard.local.json"
if [ "${BARISTA_DOCTOR_OFFLINE:-0}" = "1" ]; then
  OFFLINE=1
fi

WINDOW_MANAGER_MODE="auto"
RUNTIME_BACKEND="auto"
PROFILE_VARIANT="unknown"
MENU_PACKS_JSON='[]'
if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  WINDOW_MANAGER_MODE="$(jq -r '.modes.window_manager // "auto"' "$STATE_FILE" 2>/dev/null || echo auto)"
  RUNTIME_BACKEND="$(jq -r '.modes.runtime_backend // "auto"' "$STATE_FILE" 2>/dev/null || echo auto)"
  if [ -n "$(jq -r '.paths.code_dir // empty' "$STATE_FILE" 2>/dev/null || true)" ]; then
    CODE_DIR="$(expand_home "$(jq -r '.paths.code_dir' "$STATE_FILE")")"
  fi
  PROFILE_VARIANT="$(jq -r '.machine.profile_variant // .profile // "unknown"' "$STATE_FILE" 2>/dev/null || echo unknown)"
  MENU_PACKS_JSON="$(jq -c '.machine.menu_packs // []' "$STATE_FILE" 2>/dev/null || echo '[]')"
fi
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_DIR/data/machine.local.json" ]; then
  PROFILE_VARIANT="$(jq -r --arg fallback "$PROFILE_VARIANT" '.profile_variant // $fallback' "$CONFIG_DIR/data/machine.local.json" 2>/dev/null || echo "$PROFILE_VARIANT")"
  MENU_PACKS_JSON="$(jq -c --argjson fallback "$MENU_PACKS_JSON" '.menu_packs // $fallback' "$CONFIG_DIR/data/machine.local.json" 2>/dev/null || echo "$MENU_PACKS_JSON")"
fi

load_onboard_config() {
  if ! command -v jq >/dev/null 2>&1; then
    ONBOARD_CONFIG_JSON="{}"
    return 1
  fi
  if [ ! -f "$ONBOARD_DEFAULTS" ]; then
    ONBOARD_CONFIG_JSON="{}"
    return 1
  fi
  if [ -f "$ONBOARD_LOCAL" ]; then
    ONBOARD_CONFIG_JSON="$(jq -c -s '
      .[0] as $base | .[1] as $over
      | ($base * $over)
      | .checks = (($base.checks // {}) + ($over.checks // {}))
      | .extension_packs = (($base.extension_packs // {}) + ($over.extension_packs // {}))
    ' "$ONBOARD_DEFAULTS" "$ONBOARD_LOCAL")"
  else
    ONBOARD_CONFIG_JSON="$(jq -c '.' "$ONBOARD_DEFAULTS")"
  fi
}

severity_for_check() {
  local key="$1"
  local default_severity="${2:-warn}"
  if [ -z "$ONBOARD_CONFIG_JSON" ] || [ "$ONBOARD_CONFIG_JSON" = "{}" ]; then
    printf '%s\n' "$default_severity"
    return
  fi
  jq -r --arg key "$key" --arg default "$default_severity" \
    '.checks[$key] // $default' <<<"$ONBOARD_CONFIG_JSON"
}

emit_check() {
  local severity="$1"
  local message="$2"
  case "$severity" in
    fail) log_fail "$message" ;;
    warn) log_warn "$message" ;;
    ok) log_ok "$message" ;;
    *) log_warn "$message" ;;
  esac
}

expand_onboard_path() {
  local raw="$1"
  raw="${raw//%CONFIG%/$CONFIG_DIR}"
  raw="${raw//\$\{CONFIG_DIR\}/$CONFIG_DIR}"
  raw="${raw//%CODE%/$CODE_DIR}"
  raw="${raw//\$\{CODE_DIR\}/$CODE_DIR}"
  raw="${raw//%HOME%/$HOME}"
  raw="${raw//\$\{HOME\}/$HOME}"
  expand_home "$raw"
}

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
    "$CONFIG_DIR/scripts/machine_profile.py"
    "$CONFIG_DIR/scripts/detect_capabilities.sh"
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

check_onboard_open_local_workflow() {
  local severity
  severity="$(severity_for_check open_local_workflow fail)"
  if [ -x "$CONFIG_DIR/scripts/open_local_workflow.sh" ]; then
    log_ok "Shared workflow runner present: scripts/open_local_workflow.sh"
  else
    emit_check "$severity" "Shared workflow runner missing: $CONFIG_DIR/scripts/open_local_workflow.sh"
  fi
}

check_onboard_shortcut_mode_source() {
  local severity items_file
  severity="$(severity_for_check shortcut_mode_source warn)"
  items_file="$CONFIG_DIR/modules/items_left.lua"
  if [ -f "$items_file" ] && grep -Eq 'shortcut_mode' "$items_file"; then
    log_ok "shortcut_mode indicator is defined in items_left.lua"
  else
    emit_check "$severity" "shortcut_mode indicator missing from items_left.lua"
  fi
  if [ "${OFFLINE:-0}" -eq 0 ] \
    && command -v sketchybar >/dev/null 2>&1 \
    && pgrep -x sketchybar >/dev/null 2>&1; then
    if sketchybar --query shortcut_mode >/dev/null 2>&1; then
      log_ok "Live shortcut_mode item is queryable"
    else
      emit_check warn "Live shortcut_mode item is not queryable yet; reload SketchyBar after install"
    fi
  fi
}

check_onboard_generated_shortcuts() {
  local severity summary
  severity="$(severity_for_check generated_shortcuts warn)"
  if [ "${OFFLINE:-0}" -eq 1 ]; then
    if [ -x "$CONFIG_DIR/scripts/yabai_control.sh" ]; then
      log_ok "Offline mode: shortcut doctor binary present"
    else
      emit_check "$severity" "Cannot verify generated shortcuts without yabai_control.sh"
    fi
    return
  fi
  if [ ! -x "$CONFIG_DIR/scripts/yabai_control.sh" ]; then
    emit_check "$severity" "Cannot verify generated shortcuts without yabai_control.sh"
    return
  fi
  summary="$("$CONFIG_DIR/scripts/yabai_control.sh" doctor 2>/dev/null | awk -F': ' '/skhd shortcut summary:/{print $2; exit}' || true)"
  if [ -z "$summary" ]; then
    emit_check "$severity" "Could not read generated shortcut summary"
    return
  fi
  if printf '%s\n' "$summary" | grep -Eq 'duplicates=0' \
    && printf '%s\n' "$summary" | grep -Eq 'raw_yabai=0' \
    && printf '%s\n' "$summary" | grep -Eq 'missing_targets=0'; then
    log_ok "Generated shortcuts healthy ($summary)"
  else
    emit_check "$severity" "Generated shortcuts need attention ($summary)"
  fi
}

check_onboard_machine_profile() {
  local severity machine_file
  severity="$(severity_for_check machine_profile warn)"
  machine_file="$CONFIG_DIR/data/machine.local.json"
  if [ -f "$machine_file" ]; then
    log_ok "Machine profile present: variant=$PROFILE_VARIANT packs=$MENU_PACKS_JSON"
  else
    emit_check "$severity" "Machine profile missing: $machine_file"
  fi
}

check_onboard_extension_packs() {
  local severity pack local_rel local_file enabled
  severity="$(severity_for_check extension_pack_when_enabled warn)"
  if [ -z "$ONBOARD_CONFIG_JSON" ] || [ "$ONBOARD_CONFIG_JSON" = "{}" ]; then
    return
  fi
  while IFS= read -r pack; do
    [ -n "$pack" ] || continue
    enabled="$(jq -r --arg pack "$pack" --argjson packs "$MENU_PACKS_JSON" '
      ($packs | index($pack)) != null
    ' <<<"$ONBOARD_CONFIG_JSON")"
    if [ "$enabled" != "true" ]; then
      continue
    fi
    local_rel="$(jq -r --arg pack "$pack" '.extension_packs[$pack].local // empty' <<<"$ONBOARD_CONFIG_JSON")"
    [ -n "$local_rel" ] || continue
    local_file="$CONFIG_DIR/$local_rel"
    if [ -f "$local_file" ]; then
      log_ok "Enabled pack '$pack' has local extensions: $local_rel"
    else
      emit_check "$severity" "Pack '$pack' is enabled but $local_rel is missing (run scripts/enable_extension_pack.sh --pack $pack)"
    fi
  done < <(jq -r '.extension_packs | keys[]' <<<"$ONBOARD_CONFIG_JSON")
}

check_onboard_expected_tools() {
  local tool_json id label kind severity candidate resolved found
  if [ -z "$ONBOARD_CONFIG_JSON" ] || [ "$ONBOARD_CONFIG_JSON" = "{}" ]; then
    return
  fi
  while IFS= read -r tool_json; do
    [ -n "$tool_json" ] || continue
    id="$(jq -r '.id // "tool"' <<<"$tool_json")"
    label="$(jq -r '.label // .id // "tool"' <<<"$tool_json")"
    kind="$(jq -r '.kind // "command"' <<<"$tool_json")"
    severity="$(jq -r '.severity // "warn"' <<<"$tool_json")"
    found=0
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      resolved="$(expand_onboard_path "$candidate")"
      case "$kind" in
        path)
          if [ -e "$resolved" ]; then
            found=1
            break
          fi
          ;;
        *)
          if command -v "$candidate" >/dev/null 2>&1; then
            found=1
            break
          fi
          if [ -x "$resolved" ]; then
            found=1
            break
          fi
          ;;
      esac
    done < <(jq -r '.candidates[]?' <<<"$tool_json")
    if [ "$found" -eq 1 ]; then
      log_ok "Local tool ready: $label"
    else
      emit_check "$severity" "Local tool missing: $label ($id)"
    fi
  done < <(jq -c '.expected_tools[]?' <<<"$ONBOARD_CONFIG_JSON")
}

check_onboard_workflow_groups() {
  local group local_file
  if [ -z "$ONBOARD_CONFIG_JSON" ] || [ "$ONBOARD_CONFIG_JSON" = "{}" ]; then
    return
  fi
  local_file="$CONFIG_DIR/data/interface_extensions.local.json"
  if [ ! -f "$local_file" ]; then
    if jq -e '.expected_workflow_groups | length > 0' <<<"$ONBOARD_CONFIG_JSON" >/dev/null 2>&1; then
      emit_check warn "Expected workflow groups configured, but interface_extensions.local.json is absent"
    fi
    return
  fi
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    if jq -e --arg group "$group" '
        (if type == "array" then . else (.items // []) end)
        | map(.workflow_group // empty)
        | index($group) != null
      ' "$local_file" >/dev/null; then
      log_ok "Local workflow group present: $group"
    else
      emit_check warn "Local workflow group missing: $group"
    fi
  done < <(jq -r '.expected_workflow_groups[]?' <<<"$ONBOARD_CONFIG_JSON")
}

run_onboard_checks() {
  if ! load_onboard_config; then
    log_warn "Onboard defaults missing or jq unavailable; skipping portable onboard checks"
    return
  fi
  if [ -f "$ONBOARD_LOCAL" ]; then
    log_ok "Onboard config loaded (defaults+local)"
  else
    log_ok "Onboard config loaded (portable defaults only)"
  fi
  check_onboard_open_local_workflow
  check_onboard_shortcut_mode_source
  check_onboard_generated_shortcuts
  check_onboard_machine_profile
  check_onboard_extension_packs
  check_onboard_expected_tools
  check_onboard_workflow_groups
}

log_ok "barista-doctor start (config=$CONFIG_DIR)"
check_binary sketchybar required
check_binary jq required

case "$WINDOW_MANAGER_MODE" in
  disabled)
    check_binary yabai optional
    check_binary skhd optional
    if [ "$OFFLINE" -eq 0 ]; then
      check_process sketchybar required
      check_process yabai optional
      check_process skhd optional
    else
      log_ok "Offline mode: skipped live process checks"
    fi
    ;;
  *)
    check_binary yabai required
    check_binary skhd required
    if [ "$OFFLINE" -eq 0 ]; then
      check_process sketchybar required
      check_process yabai required
      check_process skhd required
    else
      log_ok "Offline mode: skipped live process checks"
    fi
    ;;
esac

check_state_json
check_runtime_backend
check_fonts
check_wrapper_paths
check_script_permissions
if [ "$OFFLINE" -eq 0 ]; then
  check_launch_agent
  check_skhd_shortcuts
else
  log_ok "Offline mode: skipped LaunchAgent and live shortcut doctor"
fi

if [ "$ONBOARD" -eq 1 ]; then
  run_onboard_checks
fi

if [ "$REPORT" -eq 1 ]; then
  printf 'doctor.report.status=%s\n' "$( [ "$FAIL_COUNT" -eq 0 ] && printf ok || printf fail )"
  printf 'doctor.report.fail_count=%s\n' "$FAIL_COUNT"
  printf 'doctor.report.warn_count=%s\n' "$WARN_COUNT"
  printf 'doctor.report.ok_count=%s\n' "$OK_COUNT"
  printf 'doctor.report.fix_mode=%s\n' "$FIX"
  printf 'doctor.report.onboard_mode=%s\n' "$ONBOARD"
  printf 'doctor.report.offline_mode=%s\n' "$OFFLINE"
  printf 'doctor.report.config_dir=%s\n' "$CONFIG_DIR"
  printf 'doctor.report.state_file=%s\n' "$STATE_FILE"
  printf 'doctor.report.runtime_backend=%s\n' "$RUNTIME_BACKEND"
  printf 'doctor.report.profile_variant=%s\n' "$PROFILE_VARIANT"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
