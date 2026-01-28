#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
CODE_DIR="${BARISTA_CODE_DIR:-$HOME/src}"

SYSHELP_PANEL=""
if command -v syshelp-panel >/dev/null 2>&1; then
  SYSHELP_PANEL="$(command -v syshelp-panel)"
elif [ -x "$HOME/.local/bin/syshelp-panel" ]; then
  SYSHELP_PANEL="$HOME/.local/bin/syshelp-panel"
elif [ -x "$CODE_DIR/lab/sys_manual/build/syshelp-panel" ]; then
  SYSHELP_PANEL="$CODE_DIR/lab/sys_manual/build/syshelp-panel"
elif [ -x "$CODE_DIR/sys_manual/build/syshelp-panel" ]; then
  SYSHELP_PANEL="$CODE_DIR/sys_manual/build/syshelp-panel"
fi

if [ -n "$SYSHELP_PANEL" ]; then
  "$SYSHELP_PANEL" toggle
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

FALLBACK_DOC="$CONFIG_DIR/docs/features/ICONS_AND_SHORTCUTS.md"
if [ -f "$FALLBACK_DOC" ]; then
  open "$FALLBACK_DOC" >/dev/null 2>&1 || true
else
  open "$CONFIG_DIR/README.md" >/dev/null 2>&1 || true
fi
