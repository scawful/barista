#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"

ICON_BROWSER_BIN=""
if [ -x "$CONFIG_DIR/gui/bin/icon_browser" ]; then
  ICON_BROWSER_BIN="$CONFIG_DIR/gui/bin/icon_browser"
elif [ -x "$CONFIG_DIR/build/bin/icon_browser" ]; then
  ICON_BROWSER_BIN="$CONFIG_DIR/build/bin/icon_browser"
fi

if [ -n "$ICON_BROWSER_BIN" ]; then
  nohup "$ICON_BROWSER_BIN" >/dev/null 2>&1 &
  disown
  exit 0
fi

FALLBACK_DOC="$CONFIG_DIR/docs/features/ICON_REFERENCE.md"
if [ -f "$FALLBACK_DOC" ]; then
  open "$FALLBACK_DOC" >/dev/null 2>&1 || true
else
  open "$CONFIG_DIR/README.md" >/dev/null 2>&1 || true
fi
