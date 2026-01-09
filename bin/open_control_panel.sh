#!/bin/bash
# Launch the unified Barista control panel (builds if needed).

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
CODE_DIR="${BARISTA_CODE_DIR:-${CODE_DIR:-$HOME/src}}"
GUI_DIR="$CONFIG_DIR/gui"
PANEL_BIN="$GUI_DIR/bin/config_menu"
PANEL_FALLBACKS=("$GUI_DIR/bin/config_menu_v2" "$GUI_DIR/bin/config_menu_enhanced")
LOG_FILE="${TMPDIR:-/tmp}/barista_control_panel.log"
APP_BUNDLE="$GUI_DIR/BaristaControlPanel.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_INFO="$APP_CONTENTS/Info.plist"
APP_EXEC="config_menu"
STATE_FILE="$CONFIG_DIR/state.json"
DOC_FALLBACK="$CONFIG_DIR/docs/guides/TUI_CONFIGURATION.md"

CONTROL_PREF="${BARISTA_CONTROL_PANEL:-${BARISTA_CONTROL_PANEL_MODE:-}}"
CUSTOM_COMMAND="${BARISTA_CONTROL_PANEL_CMD:-}"
IMGUICLI_BIN="${BARISTA_IMGUI_BIN:-}"

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
  esac
  shift || true
done

if [[ -z "$CONTROL_PREF" ]]; then
  CONTROL_PREF="$(read_state_value '.control_panel.preferred // empty')"
fi
if [[ -z "$CUSTOM_COMMAND" ]]; then
  CUSTOM_COMMAND="$(read_state_value '.control_panel.command // empty')"
fi

if [[ "$CONTROL_PREF" == "null" ]]; then
  CONTROL_PREF=""
fi
if [[ "$CUSTOM_COMMAND" == "null" ]]; then
  CUSTOM_COMMAND=""
fi

CONTROL_PREF="${CONTROL_PREF:-native}"

# Check if we're in the source directory (for development)
SOURCE_DIR="${BARISTA_SOURCE_DIR:-$CODE_DIR/lab/barista}"
if [ "${BARISTA_USE_SOURCE_GUI:-0}" = "1" ] && [ -x "${SOURCE_DIR}/build/bin/config_menu" ]; then
  echo "[barista] Launching control panel from source (logs: $LOG_FILE)"
  nohup "${SOURCE_DIR}/build/bin/config_menu" >"$LOG_FILE" 2>&1 &
  disown
  exit 0
fi

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

# Use installed binary
if [[ ! -x "$PANEL_BIN" ]]; then
  for candidate in "${PANEL_FALLBACKS[@]}"; do
    if [ -x "$candidate" ]; then
      PANEL_BIN="$candidate"
      break
    fi
  done
fi

if [[ ! -x "$PANEL_BIN" ]]; then
  if [[ -d "$GUI_DIR" ]]; then
    echo "[barista] Building control panel…"
    cd "$GUI_DIR" || exit 1
    if command -v cmake &> /dev/null; then
      cd "${SOURCE_DIR}" || exit 1
      ./rebuild_gui.sh 2>&1 | tail -5
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

create_app_bundle() {
  mkdir -p "$APP_MACOS"
  cat > "$APP_INFO" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${APP_EXEC}</string>
  <key>CFBundleIdentifier</key>
  <string>com.scawful.barista.controlpanel</string>
  <key>CFBundleName</key>
  <string>Barista Control Panel</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
  cp -f "$PANEL_BIN" "$APP_MACOS/$APP_EXEC"
}

if pgrep -x "config_menu" >/dev/null 2>&1; then
  pkill -x "config_menu" >/dev/null 2>&1 || true
  sleep 0.2
fi

create_app_bundle

if command -v open >/dev/null 2>&1; then
  echo "[barista] Launching control panel via app bundle"
  if ! open -na "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "[barista] Failed to launch app bundle, falling back (logs: $LOG_FILE)" >&2
    nohup "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
    disown
  fi
else
  echo "[barista] Launching control panel (logs: $LOG_FILE)"
  nohup "$PANEL_BIN" >"$LOG_FILE" 2>&1 &
  disown
fi
