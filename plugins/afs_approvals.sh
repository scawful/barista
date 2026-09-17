#!/usr/bin/env bash
# AFS approvals badge.
#
# Shows how many agent-gate requests are waiting for a human decision
# (~/.config/afs/agents/approvals.json). Hidden while nothing is pending, so
# the badge itself is the notification. The popup lists the oldest rows;
# clicking one opens a terminal with bin/afs-approvals-review, because the
# decision must be typed on a real tty (`afs approvals approve` re-asks for the
# agent:action token). Nothing here approves anything by itself.
#
# Actions:  refresh (default) | review [request_id] | list
# Test seams (env): AFS_APPROVALS_FILE, BARISTA_SKETCHYBAR_BIN,
#   BARISTA_GHOSTTY_APP, BARISTA_AFS_REVIEWER, BARISTA_AFS_APPROVALS_ROWS

set -euo pipefail

PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

_d="${0%/*}"
[ -z "$_d" ] && _d="."
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-afs_approvals}"
ACTION="${1:-refresh}"
REQUEST_ID="${2:-}"
# Same resolution as afs.runtime_paths.default_config_root():
# AFS_CONFIG_HOME, else $XDG_CONFIG_HOME/afs, else ~/.config/afs.
if [ -n "${AFS_CONFIG_HOME:-}" ]; then
  AFS_CONFIG_DIR="$AFS_CONFIG_HOME"
else
  AFS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/afs"
fi
APPROVALS_FILE="${AFS_APPROVALS_FILE:-$AFS_CONFIG_DIR/agents/approvals.json}"
REVIEWER="${BARISTA_AFS_REVIEWER:-${_d}/../bin/afs-approvals-review}"
MAX_ROWS="${BARISTA_AFS_APPROVALS_ROWS:-5}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"

ICON="${BARISTA_AFS_APPROVALS_ICON:-󰡁}"
COLOR_PENDING="${BARISTA_AFS_APPROVALS_COLOR:-0xfff9e2af}"
COLOR_TEXT="0xffcdd6f4"
COLOR_MUTED="0xff6c7086"

sb_set() {
  "$SKETCHYBAR_BIN" --set "$@" >/dev/null 2>&1 || true
}

# Pending requests as a compact JSON array. The file is a list of request
# objects (ApprovalGate) but tolerate a {"requests": [...]} wrapper too.
pending_json() {
  if [ ! -r "$APPROVALS_FILE" ] || ! command -v jq >/dev/null 2>&1; then
    printf '[]'
    return 0
  fi
  jq -c '
    (if type == "array" then . else (.requests // []) end)
    | map(select((.status // "") == "pending"))
    | sort_by(.timestamp // "")
  ' "$APPROVALS_FILE" 2>/dev/null || printf '[]'
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

review_command() {
  local rid="${1:-}"
  local cmd
  cmd="$(shell_quote "$REVIEWER")"
  [ -n "$rid" ] && cmd="$cmd --request-id $(shell_quote "$rid")"
  printf '%s' "$cmd"
}

open_terminal() {
  local cmd="$1"
  local ghostty="${BARISTA_GHOSTTY_APP:-/Applications/Ghostty.app}"
  if [ -d "$ghostty" ]; then
    open -na "$ghostty" --args -e /bin/zsh -lc "$cmd" >/dev/null 2>&1 || true
    return 0
  fi
  # AppleScript string literal: JSON escaping is a superset of what it needs.
  local quoted
  quoted="$(printf '%s' "$cmd" | jq -Rs . 2>/dev/null || printf '"%s"' "$cmd")"
  osascript -e "tell application \"Terminal\" to activate" \
            -e "tell application \"Terminal\" to do script $quoted" >/dev/null 2>&1 || true
}

refresh_status() {
  local pending count
  pending="$(pending_json)"
  count="$(printf '%s' "$pending" | jq 'length' 2>/dev/null || printf 0)"

  if [ "${count:-0}" -eq 0 ]; then
    sb_set "$NAME" drawing=off popup.drawing=off label=""
    sb_set "${NAME}.summary" label="Nothing pending" icon.color="$COLOR_MUTED"
    local i=1
    while [ "$i" -le "$MAX_ROWS" ]; do
      sb_set "${NAME}.row.${i}" drawing=off
      i=$((i + 1))
    done
    return 0
  fi

  local oldest
  oldest="$(printf '%s' "$pending" | jq -r '.[0].timestamp // "" | .[0:10]')"
  sb_set "$NAME" drawing=on icon="$ICON" icon.color="$COLOR_PENDING" \
    label="$count" label.color="$COLOR_TEXT"
  sb_set "${NAME}.summary" \
    label="$count pending · oldest $oldest" icon.color="$COLOR_PENDING"

  local i=1
  while [ "$i" -le "$MAX_ROWS" ]; do
    if [ "$i" -le "$count" ]; then
      local idx=$((i - 1)) rid agent action detail label
      rid="$(printf '%s' "$pending" | jq -r ".[$idx].request_id // \"\"")"
      agent="$(printf '%s' "$pending" | jq -r ".[$idx].agent // \"?\"")"
      action="$(printf '%s' "$pending" | jq -r ".[$idx].action // \"?\"")"
      detail="$(printf '%s' "$pending" | jq -r ".[$idx].detail // \"\" | .[0:44]")"
      label="$agent · $action"
      [ -n "$detail" ] && label="$label — $detail"
      sb_set "${NAME}.row.${i}" drawing=on label="$label" \
        click_script="$0 review $(shell_quote "$rid")" icon.color="$COLOR_PENDING"
    else
      sb_set "${NAME}.row.${i}" drawing=off
    fi
    i=$((i + 1))
  done
}

case "${SENDER:-}" in
  mouse.entered)
    if type highlight_with_timeout >/dev/null 2>&1; then
      highlight_with_timeout "$NAME" "background.drawing=on background.color=$HIGHLIGHT" "background.drawing=off"
    fi
    exit 0
    ;;
  mouse.exited)
    if type clear_highlight >/dev/null 2>&1; then
      clear_highlight "$NAME" "background.drawing=off"
    fi
    exit 0
    ;;
  mouse.exited.global)
    sb_set "$NAME" popup.drawing=off
    if type clear_highlight >/dev/null 2>&1; then
      clear_highlight "$NAME" "background.drawing=off"
    fi
    exit 0
    ;;
esac

case "$ACTION" in
  refresh|"")
    refresh_status
    ;;
  review)
    sb_set "$NAME" popup.drawing=off
    open_terminal "$(review_command "$REQUEST_ID")"
    ;;
  list)
    pending_json
    printf '\n'
    ;;
  *)
    refresh_status
    ;;
esac
