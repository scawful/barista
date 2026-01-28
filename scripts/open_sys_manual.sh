#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"

SYS_MANUAL_BIN=""
if [ -x "$CODE_DIR/lab/sys_manual/build/sys_manual" ]; then
  SYS_MANUAL_BIN="$CODE_DIR/lab/sys_manual/build/sys_manual"
elif [ -x "$CODE_DIR/sys_manual/build/sys_manual" ]; then
  SYS_MANUAL_BIN="$CODE_DIR/sys_manual/build/sys_manual"
elif [ -x "/Applications/sys_manual.app/Contents/MacOS/sys_manual" ]; then
  SYS_MANUAL_BIN="/Applications/sys_manual.app/Contents/MacOS/sys_manual"
fi

if [ -n "$SYS_MANUAL_BIN" ]; then
  nohup "$SYS_MANUAL_BIN" >/dev/null 2>&1 &
  disown
  exit 0
fi

HELP_CENTER_BIN=""
if [ -x "$CONFIG_DIR/gui/bin/help_center" ]; then
  HELP_CENTER_BIN="$CONFIG_DIR/gui/bin/help_center"
elif [ -x "$CONFIG_DIR/build/bin/help_center" ]; then
  HELP_CENTER_BIN="$CONFIG_DIR/build/bin/help_center"
fi

if [ -n "$HELP_CENTER_BIN" ]; then
  nohup "$HELP_CENTER_BIN" >/dev/null 2>&1 &
  disown
  exit 0
fi

FALLBACK_DOC="$CONFIG_DIR/docs/guides/QUICK_START.md"
if [ -f "$FALLBACK_DOC" ]; then
  open "$FALLBACK_DOC" >/dev/null 2>&1 || true
else
  open "$CONFIG_DIR/README.md" >/dev/null 2>&1 || true
fi
