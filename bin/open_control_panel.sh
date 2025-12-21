#!/bin/bash
# Launch the unified Barista control panel (builds if needed).

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
GUI_DIR="$CONFIG_DIR/gui"
PANEL_BIN="$GUI_DIR/bin/config_menu"
PANEL_FALLBACKS=("$GUI_DIR/bin/config_menu_v2" "$GUI_DIR/bin/config_menu_enhanced")
LOG_FILE="${TMPDIR:-/tmp}/barista_control_panel.log"
APP_BUNDLE="$GUI_DIR/BaristaControlPanel.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_INFO="$APP_CONTENTS/Info.plist"
APP_EXEC="config_menu"

# Check if we're in the source directory (for development)
SOURCE_DIR="${HOME}/Code/barista"
if [ "${BARISTA_USE_SOURCE_GUI:-0}" = "1" ] && [ -x "${SOURCE_DIR}/build/bin/config_menu" ]; then
  echo "[barista] Launching control panel from source (logs: $LOG_FILE)"
  nohup "${SOURCE_DIR}/build/bin/config_menu" >"$LOG_FILE" 2>&1 &
  disown
  exit 0
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
      cd "${SOURCE_DIR:-$HOME/Code/barista}" || exit 1
      ./rebuild_gui.sh 2>&1 | tail -5
    else
      echo "[barista] CMake not found. Install with: brew install cmake" >&2
      exit 1
    fi
  else
    echo "[barista] GUI sources not found at $GUI_DIR" >&2
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
