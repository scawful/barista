#!/bin/bash
# Launch the unified Barista control panel (builds if needed).

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
CODE_DIR="${BARISTA_CODE_DIR:-${CODE_DIR:-$HOME/src}}"
GUI_DIR="$CONFIG_DIR/gui"
PANEL_BIN="$GUI_DIR/bin/config_menu"
PANEL_FALLBACKS=("$GUI_DIR/bin/config_menu_v2" "$GUI_DIR/bin/config_menu_enhanced")
LOG_FILE="${TMPDIR:-/tmp}/barista_control_panel.log"
PANEL_APP="$GUI_DIR/Barista.app"
APP_EXEC="Barista"
APP_NAME="Barista"
APP_BUNDLE_ID="com.scawful.barista"
LEGACY_APP_EXEC="BaristaControlPanel"
LEGACY_APP_BUNDLE_ID="com.scawful.barista.controlpanel"
INSTALLED_PANEL_APP="${BARISTA_CONTROL_PANEL_APP:-$HOME/Applications/${APP_NAME}.app}"
STATE_FILE="$CONFIG_DIR/state.json"
DOC_FALLBACK="$CONFIG_DIR/docs/guides/TUI_CONFIGURATION.md"
ORACLE_MANAGER_SCRIPT="$CONFIG_DIR/bin/open_oracle_agent_manager.sh"

CONTROL_PREF="${BARISTA_CONTROL_PANEL:-${BARISTA_CONTROL_PANEL_MODE:-}}"
CUSTOM_COMMAND="${BARISTA_CONTROL_PANEL_CMD:-}"
IMGUICLI_BIN="${BARISTA_IMGUI_BIN:-}"
RUNTIME_BACKEND="${BARISTA_RUNTIME_BACKEND:-}"
CONTROL_TAB="${BARISTA_CONTROL_TAB:-}"
WINDOW_MODE="${BARISTA_CONTROL_WINDOW_MODE:-}"
OPEN_ORACLE_MANAGER=0

read_state_value() {
  local query="$1"
  if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
    jq -r "$query" "$STATE_FILE" 2>/dev/null
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --native|--cocoa)
      CONTROL_PREF="native"
      ;;
    --imgui)
      CONTROL_PREF="imgui"
      ;;
    --tui|--cli)
      CONTROL_PREF="tui"
      ;;
    --custom)
      CONTROL_PREF="custom"
      ;;
    --command)
      shift
      CUSTOM_COMMAND="${1:-}"
      ;;
    --panel)
      ;;
    --tab)
      shift
      CONTROL_TAB="${1:-}"
      ;;
    --oracle|--oracle-manager|--oracle-agent-manager|--oam)
      OPEN_ORACLE_MANAGER=1
      ;;
  esac
  shift || true
done

if [[ -z "$CONTROL_PREF" ]]; then
  CONTROL_PREF="$(read_state_value '.control_panel.preferred // empty')"
fi
if [[ -z "$CUSTOM_COMMAND" ]]; then
  CUSTOM_COMMAND="$(read_state_value '.control_panel.command // empty')"
fi
if [[ -z "$RUNTIME_BACKEND" ]]; then
  RUNTIME_BACKEND="$(read_state_value '.modes.runtime_backend // empty')"
fi
if [[ -z "$WINDOW_MODE" ]]; then
  WINDOW_MODE="$(read_state_value '.control_panel.window_mode // empty')"
fi

if [[ "$CONTROL_PREF" == "null" ]]; then
  CONTROL_PREF=""
fi
if [[ "$CUSTOM_COMMAND" == "null" ]]; then
  CUSTOM_COMMAND=""
fi
if [[ "$RUNTIME_BACKEND" == "null" ]]; then
  RUNTIME_BACKEND=""
fi
if [[ "$WINDOW_MODE" == "null" ]]; then
  WINDOW_MODE=""
fi

if [[ -z "$CONTROL_PREF" && "$RUNTIME_BACKEND" == "lua" ]]; then
  CONTROL_PREF="tui"
fi
CONTROL_PREF="${CONTROL_PREF:-native}"
WINDOW_MODE="${WINDOW_MODE:-standard}"

SOURCE_DIR="${BARISTA_SOURCE_DIR:-$CODE_DIR/lab/barista}"

panel_app_exec() {
  local app="$1"
  if [[ -x "$app/Contents/MacOS/$APP_EXEC" ]]; then
    printf '%s/Contents/MacOS/%s' "$app" "$APP_EXEC"
  elif [[ -x "$app/Contents/MacOS/$LEGACY_APP_EXEC" ]]; then
    printf '%s/Contents/MacOS/%s' "$app" "$LEGACY_APP_EXEC"
  else
    printf '%s/Contents/MacOS/%s' "$app" "$APP_EXEC"
  fi
}

panel_app_is_runnable() {
  local app="$1"
  [[ -x "$(panel_app_exec "$app")" ]]
}

install_stable_panel_app_if_needed() {
  local source_app="$SOURCE_DIR/build/bin/${APP_EXEC}.app"
  local legacy_source_app="$SOURCE_DIR/build/bin/${LEGACY_APP_EXEC}.app"
  local source_exec installed_exec
  if [[ ! -x "$(panel_app_exec "$source_app")" && -x "$(panel_app_exec "$legacy_source_app")" ]]; then
    source_app="$legacy_source_app"
  fi
  source_exec="$(panel_app_exec "$source_app")"
  installed_exec="$(panel_app_exec "$INSTALLED_PANEL_APP")"

  if [[ ! -x "$source_exec" ]]; then
    return 0
  fi
  if [[ -x "$installed_exec" && ! "$source_exec" -nt "$installed_exec" ]]; then
    return 0
  fi
  if [[ -x "$SOURCE_DIR/scripts/install_control_panel_app.sh" ]]; then
    "$SOURCE_DIR/scripts/install_control_panel_app.sh" \
      --source "$source_app" \
      --dest "$INSTALLED_PANEL_APP" >/dev/null 2>&1 || true
  fi
}

resolve_panel_app() {
  local source_app="$SOURCE_DIR/build/bin/${APP_EXEC}.app"
  local legacy_source_app="$SOURCE_DIR/build/bin/${LEGACY_APP_EXEC}.app"
  local config_app="$CONFIG_DIR/build/bin/${APP_EXEC}.app"
  local legacy_config_app="$CONFIG_DIR/build/bin/${LEGACY_APP_EXEC}.app"
  local legacy_panel_app="$GUI_DIR/${LEGACY_APP_EXEC}.app"
  local selected=""

  install_stable_panel_app_if_needed

  if panel_app_is_runnable "$INSTALLED_PANEL_APP"; then
    selected="$INSTALLED_PANEL_APP"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$source_app"; then
    selected="$source_app"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$legacy_source_app"; then
    selected="$legacy_source_app"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$config_app"; then
    selected="$config_app"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$legacy_config_app"; then
    selected="$legacy_config_app"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$PANEL_APP"; then
    selected="$PANEL_APP"
  fi
  if [[ -z "$selected" ]] && panel_app_is_runnable "$legacy_panel_app"; then
    selected="$legacy_panel_app"
  fi

  if [[ -n "$selected" ]]; then
    PANEL_APP="$selected"
    return 0
  fi
  return 1
}

resolve_panel_bin() {
  local source_build="$SOURCE_DIR/build/bin/config_menu"
  local config_build="$CONFIG_DIR/build/bin/config_menu"
  if [[ -x "$source_build" ]]; then
    if [[ ! -x "$PANEL_BIN" || "$source_build" -nt "$PANEL_BIN" ]]; then
      PANEL_BIN="$source_build"
      return 0
    fi
  fi
  if [[ -x "$config_build" ]]; then
    if [[ ! -x "$PANEL_BIN" || "$config_build" -nt "$PANEL_BIN" ]]; then
      PANEL_BIN="$config_build"
      return 0
    fi
  fi

  local candidates=("$PANEL_BIN" "${PANEL_FALLBACKS[@]}")
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      PANEL_BIN="$candidate"
      return 0
    fi
  done
  return 1
}

resolve_imgui_bin() {
  if [[ -n "$IMGUICLI_BIN" && -x "$IMGUICLI_BIN" ]]; then
    echo "$IMGUICLI_BIN"
    return 0
  fi
  if command -v barista_config >/dev/null 2>&1; then
    command -v barista_config
    return 0
  fi
  local candidates=(
    "$CODE_DIR/lab/barista_config/build/barista_config"
    "$CODE_DIR/barista_config/build/barista_config"
    "$HOME/.local/bin/barista_config"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

launch_custom_panel() {
  if [[ -z "$CUSTOM_COMMAND" ]]; then
    return 1
  fi
  echo "[barista] Launching custom control panel"
  nohup bash -lc "$CUSTOM_COMMAND" >"$LOG_FILE" 2>&1 &
  disown
  return 0
}

launch_imgui_panel() {
  local bin
  bin="$(resolve_imgui_bin || true)"
  if [[ -z "$bin" ]]; then
    return 1
  fi
  echo "[barista] Launching ImGui control panel ($bin)"
  nohup "$bin" >"$LOG_FILE" 2>&1 &
  disown
  return 0
}

launch_tui_panel() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  local tui_cmd=""
  if command -v barista >/dev/null 2>&1; then
    tui_cmd="$(command -v barista)"
  elif [[ -x "$CONFIG_DIR/bin/barista" ]]; then
    tui_cmd="$CONFIG_DIR/bin/barista"
  elif [[ -x "$SOURCE_DIR/bin/barista" ]]; then
    tui_cmd="$SOURCE_DIR/bin/barista"
  fi

  if [[ -z "$tui_cmd" ]]; then
    return 1
  fi

  echo "[barista] Launching TUI control panel ($tui_cmd)"
  nohup "$tui_cmd" >"$LOG_FILE" 2>&1 &
  disown
  return 0
}

launch_manual_fallback() {
  echo "[barista] Falling back to manual config edit" >&2
  if command -v open >/dev/null 2>&1; then
    [[ -f "$STATE_FILE" ]] && open "$STATE_FILE" >/dev/null 2>&1 || true
    [[ -f "$DOC_FALLBACK" ]] && open "$DOC_FALLBACK" >/dev/null 2>&1 || true
  else
    echo "Edit state.json: $STATE_FILE" >&2
    echo "Docs: $DOC_FALLBACK" >&2
  fi
}

launch_oracle_manager() {
  if [[ -x "$ORACLE_MANAGER_SCRIPT" ]]; then
    if "$ORACLE_MANAGER_SCRIPT"; then
      return 0
    fi
  fi
  return 1
}

apply_native_window_mode() {
  local launched_pid="$1"
  if [[ -z "$launched_pid" ]]; then
    return 0
  fi
  local normalized_mode
  normalized_mode="$(printf '%s' "$WINDOW_MODE" | tr '[:upper:]' '[:lower:]')"

  if [[ "$normalized_mode" != "utility" ]]; then
    return 0
  fi
  if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 0
  fi

  (
    for _ in $(seq 1 40); do
      local window_json
      window_json="$(yabai -m query --windows 2>/dev/null | jq -c --argjson pid "$launched_pid" 'first(.[] | select(.pid == $pid and (((.app // "") == "Barista") or ((.app // "") == "Barista Control Panel") or ((.app // "") == "BaristaControlPanel") or ((.app // "") == "config_menu"))))' 2>/dev/null || true)"
      if [[ -n "$window_json" && "$window_json" != "null" ]]; then
        local window_id is_floating
        window_id="$(jq -r '.id // empty' <<<"$window_json")"
        is_floating="$(jq -r '."is-floating" // false' <<<"$window_json")"
        if [[ -n "$window_id" && "$is_floating" != "true" ]]; then
          yabai -m window "$window_id" --toggle float >/dev/null 2>&1 || true
        fi
        break
      fi
      sleep 0.1
    done
  ) >/dev/null 2>&1 &
}

find_launched_panel_pid() {
  local process_name pid
  for _ in $(seq 1 30); do
    for process_name in "${APP_EXEC}" "${LEGACY_APP_EXEC}" "config_menu"; do
      pid="$(pgrep -x "$process_name" 2>/dev/null | tail -n 1 || true)"
      if [[ -n "$pid" ]]; then
        printf '%s' "$pid"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}

launch_panel_app_bundle() {
  if ! command -v open >/dev/null 2>&1; then
    return 1
  fi

  echo "[barista] Launching control panel via app bundle"
  if [[ -n "$CONTROL_TAB" ]]; then
    open -na "$PANEL_APP" --args --tab "$CONTROL_TAB" >"$LOG_FILE" 2>&1
  else
    open -na "$PANEL_APP" >"$LOG_FILE" 2>&1
  fi

  local launched_pid
  launched_pid="$(find_launched_panel_pid || true)"
  apply_native_window_mode "$launched_pid"
  return 0
}

if (( OPEN_ORACLE_MANAGER == 1 )); then
  if launch_oracle_manager; then
    exit 0
  fi
  echo "[barista] Oracle Agent Manager unavailable; falling back to Barista appearance panel" >&2
  CONTROL_TAB="appearance"
fi

if [[ "$CONTROL_PREF" == "custom" ]]; then
  if launch_custom_panel; then
    exit 0
  fi
  echo "[barista] Custom control panel command missing; falling back to native" >&2
  CONTROL_PREF="native"
fi

if [[ "$CONTROL_PREF" == "imgui" ]]; then
  if launch_imgui_panel; then
    exit 0
  fi
  echo "[barista] ImGui control panel not found; falling back to native" >&2
  CONTROL_PREF="native"
fi

if [[ "$CONTROL_PREF" == "tui" ]]; then
  if launch_tui_panel; then
    exit 0
  fi
  echo "[barista] TUI control panel unavailable; falling back to native" >&2
  CONTROL_PREF="native"
fi

# Prefer TUI on systems without build tooling or when explicitly requested.
if [[ "${BARISTA_TUI_ONLY:-0}" == "1" || "${BARISTA_LUA_ONLY:-0}" == "1" || "${BARISTA_NO_CMAKE:-0}" == "1" ]]; then
  if launch_tui_panel; then
    exit 0
  fi
fi

# Use built app bundle or fallback to raw binaries
resolve_panel_app || true
resolve_panel_bin || true

if ! panel_app_is_runnable "$PANEL_APP" && [[ ! -x "$PANEL_BIN" ]]; then
  if [[ -d "$GUI_DIR" ]]; then
    echo "[barista] Building control panel…"
    cd "$GUI_DIR" || exit 1
    if command -v cmake &> /dev/null; then
      cd "${SOURCE_DIR}" || exit 1
      ./rebuild_gui.sh 2>&1 | tail -5
      resolve_panel_app || true
      resolve_panel_bin || true
    else
      echo "[barista] CMake not found. Install with: brew install cmake" >&2
      if launch_tui_panel; then
        exit 0
      fi
      launch_manual_fallback
      exit 1
    fi
  else
    echo "[barista] GUI sources not found at $GUI_DIR" >&2
    if launch_tui_panel; then
      exit 0
    fi
    launch_manual_fallback
    exit 1
  fi
fi

for process_name in "${APP_EXEC}" "${LEGACY_APP_EXEC}" "config_menu"; do
  if pgrep -x "$process_name" >/dev/null 2>&1; then
    pkill -x "$process_name" >/dev/null 2>&1 || true
  fi
done
sleep 0.2

LAUNCH_BIN=""
if panel_app_is_runnable "$PANEL_APP"; then
  echo "[barista] Using panel bundle: $PANEL_APP"
  LAUNCH_BIN="$(panel_app_exec "$PANEL_APP")"
elif [[ -x "$PANEL_BIN" ]]; then
  echo "[barista] Using panel binary: $PANEL_BIN"
  LAUNCH_BIN="$PANEL_BIN"
else
  echo "[barista] No control panel artifact found" >&2
  if launch_tui_panel; then
    exit 0
  fi
  launch_manual_fallback
  exit 1
fi

if [[ "$LAUNCH_BIN" == *".app/Contents/MacOS/"* ]]; then
  if launch_panel_app_bundle; then
    true
  else
    echo "[barista] LaunchServices unavailable; launching bundle executable directly"
    if [[ -n "$CONTROL_TAB" ]]; then
      nohup "$LAUNCH_BIN" --tab "$CONTROL_TAB" >"$LOG_FILE" 2>&1 &
    else
      nohup "$LAUNCH_BIN" >"$LOG_FILE" 2>&1 &
    fi
    launched_pid=$!
    apply_native_window_mode "$launched_pid"
    disown
  fi
else
  echo "[barista] Launching control panel from raw binary (logs: $LOG_FILE)"
  if [[ -n "$CONTROL_TAB" ]]; then
    nohup "$PANEL_BIN" --tab "$CONTROL_TAB" >"$LOG_FILE" 2>&1 &
  else
    nohup "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
  fi
  launched_pid=$!
  apply_native_window_mode "$launched_pid"
  disown
fi

if command -v osascript >/dev/null 2>&1; then
  (sleep 0.3; osascript -e "tell application id \"${APP_BUNDLE_ID}\" to activate" >/dev/null 2>&1 || osascript -e "tell application id \"${LEGACY_APP_BUNDLE_ID}\" to activate" >/dev/null 2>&1 || true) &
fi
