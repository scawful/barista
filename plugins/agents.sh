#!/usr/bin/env bash
# Agents widget: running Codex/Claude/Cursor/Gemini sessions and usage.
#
# Actions: refresh (default) | popup (refresh plus the Local Models submenu)

set -euo pipefail

PATH="${PATH:-}:$HOME/.lmstudio/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

_d="${0%/*}"
[ -z "$_d" ] && _d="."
# shellcheck source=plugins/lib/common.sh
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-agents}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
export BARISTA_SKETCHYBAR_BIN="$SKETCHYBAR_BIN"
SESSIONS_SCRIPT="${BARISTA_AGENT_SESSIONS_SCRIPT:-${_d}/../scripts/agent_sessions.py}"
LMSTUDIO_SCRIPT="${BARISTA_LMSTUDIO_SCRIPT:-${_d}/lmstudio_model.sh}"

case "${SENDER:-}" in
  mouse.entered)
    highlight_with_timeout "$NAME" "background.drawing=on background.color=$HIGHLIGHT" "background.drawing=off"
    exit 0
    ;;
  mouse.exited)
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
esac

"$SESSIONS_SCRIPT" apply
if [ "${1:-refresh}" = "popup" ] && [ -x "$LMSTUDIO_SCRIPT" ]; then
  "$LMSTUDIO_SCRIPT" refresh
fi
