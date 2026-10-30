#!/usr/bin/env bash
# Build barista-agent and switch between the Barista dock and the native Dock.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/native/BaristaAgent"
BUILD_DIR="${BARISTA_AGENT_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/barista-agent}"
BINARY="$BUILD_DIR/release/barista-agent"
LOG_DIR="${HOME}/Library/Logs/sketchybar-barista"
LABEL="dev.barista.agent"
PLIST="${BARISTA_AGENT_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/barista"
NATIVE_SETTINGS="$STATE_DIR/native-dock.env"
DOMAIN="gui/$(id -u)"
# Long enough that the native Dock never reveals while the Barista dock runs.
HIDDEN_DELAY=1000

build() {
  swift build -c release --package-path "$PACKAGE" --scratch-path "$BUILD_DIR"
}

dock_value() {
  defaults read com.apple.dock "$1" 2>/dev/null || true
}

# `defaults read` prints booleans as 1/0 but `-bool` writes take true/false.
bool_word() {
  case "$1" in
    1) echo true ;;
    0) echo false ;;
  esac
}

restore_dock_value() {
  local key="$1" type="$2" value="$3"
  if [ -n "$value" ]; then
    defaults write com.apple.dock "$key" "-$type" "$value"
  else
    defaults delete com.apple.dock "$key" 2>/dev/null || true
  fi
}

# Paths go into XML; bash's ${var//&/...} treats & differently in 3.2 and 5.2+.
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

write_plist() {
  mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
  local binary script log
  binary="$(xml_escape "$BINARY")"
  script="$(xml_escape "$ROOT/scripts/barista_agent.sh")"
  log="$(xml_escape "$LOG_DIR/barista-agent.log")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$binary</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>BARISTA_AGENT_SCRIPT</key>
    <string>$script</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>AbandonProcessGroup</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
  <key>StandardOutPath</key>
  <string>$log</string>
  <key>StandardErrorPath</key>
  <string>$log</string>
</dict>
</plist>
EOF
}

use_barista_dock() {
  [ -x "$BINARY" ] || build
  if [ ! -f "$NATIVE_SETTINGS" ]; then
    mkdir -p "$STATE_DIR"
    printf 'autohide=%s\nautohide_delay=%s\n' \
      "$(dock_value autohide)" "$(dock_value autohide-delay)" > "$NATIVE_SETTINGS"
  fi
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float "$HIDDEN_DELAY"
  killall Dock 2>/dev/null || true
  write_plist
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "dock: barista"
}

# Runs from the agent's own menu too, so unloading the agent comes last.
use_native_dock() {
  local autohide="" autohide_delay=""
  if [ -f "$NATIVE_SETTINGS" ]; then
    autohide="$(sed -n 's/^autohide=//p' "$NATIVE_SETTINGS")"
    autohide_delay="$(sed -n 's/^autohide_delay=//p' "$NATIVE_SETTINGS")"
    restore_dock_value autohide bool "$(bool_word "$autohide")"
    restore_dock_value autohide-delay float "$autohide_delay"
    rm -f "$NATIVE_SETTINGS"
  elif [ "$(dock_value autohide-delay)" = "$HIDDEN_DELAY" ]; then
    restore_dock_value autohide-delay float ""
  fi
  killall Dock 2>/dev/null || true
  rm -f "$PLIST"
  echo "dock: native"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
}

dock_mode() {
  if [ -f "$PLIST" ]; then echo barista; else echo native; fi
}

dock() {
  case "${1:-status}" in
    barista) use_barista_dock ;;
    native) use_native_dock ;;
    toggle) if [ "$(dock_mode)" = barista ]; then use_native_dock; else use_barista_dock; fi ;;
    status) echo "dock: $(dock_mode)" ;;
    *) echo "Usage: $0 dock {barista|native|toggle|status}" >&2; return 1 ;;
  esac
}

case "${1:-}" in
  build) build ;;
  dock) dock "${2:-status}" ;;
  restart)
    build
    [ "$(dock_mode)" = native ] || launchctl kickstart -k "$DOMAIN/$LABEL"
    ;;
  view|browse|open)
    # Markdown and images in the viewer, folders in Barista Files.
    [ -n "${2:-}" ] || { echo "Usage: $0 $1 PATH" >&2; exit 1; }
    [ -x "$BINARY" ] || { echo "barista-agent is not built; run: $0 build" >&2; exit 1; }
    "$BINARY" "$1" "$2"
    ;;
  group)
    # A dock group's callout, by title (subgroups too), e.g. from a hotkey.
    [ -n "${2:-}" ] || { echo "Usage: $0 group TITLE" >&2; exit 1; }
    [ -x "$BINARY" ] || { echo "barista-agent is not built; run: $0 build" >&2; exit 1; }
    "$BINARY" group "$2"
    ;;
  gallery)
    # A folder's pictures and movies as thumbnails; a file opens its folder.
    [ -n "${2:-}" ] || { echo "Usage: $0 gallery PATH" >&2; exit 1; }
    [ -x "$BINARY" ] || { echo "barista-agent is not built; run: $0 build" >&2; exit 1; }
    "$BINARY" gallery "$2"
    ;;
  collection)
    # A named collection from data/barista_collections.local.json.
    [ -n "${2:-}" ] || { echo "Usage: $0 collection NAME" >&2; exit 1; }
    [ -x "$BINARY" ] || { echo "barista-agent is not built; run: $0 build" >&2; exit 1; }
    "$BINARY" collection "$2"
    ;;
  *)
    echo "Usage: $0 {build|dock {barista|native|toggle|status}|restart|view PATH|browse PATH|open PATH|group TITLE|gallery PATH|collection NAME}" >&2
    exit 1
    ;;
esac
