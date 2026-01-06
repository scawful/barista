#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"

if [[ -z "$YABAI_BIN" ]]; then
  echo "yabai not found in PATH." >&2
  exit 1
fi

require_jq() {
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is required for this command." >&2
    exit 1
  fi
}

current_space_index() {
  require_jq
  "$YABAI_BIN" -m query --spaces --space | "$JQ_BIN" -r '.index'
}

current_space_layout() {
  require_jq
  "$YABAI_BIN" -m query --spaces --space | "$JQ_BIN" -r '.type'
}

display_space_indices() {
  require_jq
  "$YABAI_BIN" -m query --spaces --display | "$JQ_BIN" -r '.[].index'
}

neighbor_space_index() {
  local direction="$1"
  mapfile -t spaces < <(display_space_indices)
  local count=${#spaces[@]}
  if (( count == 0 )); then
    return 1
  fi

  local current
  current=$(current_space_index)
  local pos=-1
  for i in "${!spaces[@]}"; do
    if [[ "${spaces[$i]}" == "$current" ]]; then
      pos=$i
      break
    fi
  done

  if (( pos < 0 )); then
    return 1
  fi

  if [[ "$direction" == "next" ]]; then
    echo "${spaces[$(( (pos + 1) % count ))]}"
  else
    echo "${spaces[$(( (pos - 1 + count) % count ))]}"
  fi
}

space_focus_safe() {
  local target="$1"
  local direction="${2:-$target}"
  if "$YABAI_BIN" -m space --focus "$target" >/dev/null 2>&1; then
    return 0
  fi

  case "$direction" in
    next)
      osascript -e 'tell application "System Events" to key code 124 using control down' >/dev/null 2>&1
      return 0
      ;;
    prev)
      osascript -e 'tell application "System Events" to key code 123 using control down' >/dev/null 2>&1
      return 0
      ;;
  esac

  echo "space focus failed (scripting addition likely missing)" >&2
  return 1
}

space_focus_wrap() {
  local direction="$1"
  local target
  target=$(neighbor_space_index "$direction") || return 1
  space_focus_safe "$target" "$direction"
}

window_space_wrap() {
  local direction="$1"
  local target
  target=$(neighbor_space_index "$direction") || return 1
  "$YABAI_BIN" -m window --space "$target"
}

space_focus_app() {
  local app="$1"
  if [[ -z "$app" ]]; then
    echo "Usage: $0 space-focus-app <AppName>" >&2
    exit 1
  fi
  require_jq
  local space
  space=$("$YABAI_BIN" -m query --windows | "$JQ_BIN" -r --arg app "$app" '.[] | select(.app == $app) | .space' | head -n 1)
  if [[ -z "$space" ]]; then
    echo "No window found for app: $app" >&2
    exit 1
  fi
  space_focus_safe "$space"
}

window_center() {
  "$YABAI_BIN" -m window --grid 4:4:1:1:2:2
}

restart_yabai() {
  if "$YABAI_BIN" --restart-service >/dev/null 2>&1; then
    echo "yabai restarted"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services restart yabai >/dev/null 2>&1
    echo "yabai restarted via brew"
    return 0
  fi
  echo "Unable to restart yabai." >&2
  return 1
}

run_doctor() {
  local ok=1
  if ! pgrep -x yabai >/dev/null 2>&1; then
    echo "yabai: not running"
    ok=0
  else
    echo "yabai: running"
  fi

  if ! pgrep -x skhd >/dev/null 2>&1; then
    echo "skhd: not running"
    ok=0
  else
    echo "skhd: running"
  fi

  if command -v jq >/dev/null 2>&1; then
    local current
    if current=$(current_space_index 2>/dev/null); then
      echo "current space: $current"
      if output=$("$YABAI_BIN" -m space --focus "$current" 2>&1); then
        echo "space focus ok"
      elif echo "$output" | grep -q "already focused space"; then
        echo "space focus ok"
      else
        echo "space focus failed (scripting addition likely missing)" >&2
        ok=0
      fi
    else
      echo "unable to query spaces" >&2
      ok=0
    fi
  else
    echo "jq not found; skipping space query" >&2
  fi

  if (( ok == 1 )); then
    echo "doctor: ok"
    return 0
  fi
  return 1
}

command=${1:-}
shift || true

case "$command" in
  status)
    layout=$(current_space_layout)
    current=$(current_space_index)
    echo "layout: $layout"
    echo "current space: $current"
    ;;
  restart)
    restart_yabai
    ;;
  balance)
    "$YABAI_BIN" -m space --balance
    ;;
  space-rotate|rotate)
    "$YABAI_BIN" -m space --rotate 90
    ;;
  mirror)
    "$YABAI_BIN" -m space --mirror x-axis
    ;;
  space-mirror-x)
    "$YABAI_BIN" -m space --mirror x-axis
    ;;
  space-mirror-y)
    "$YABAI_BIN" -m space --mirror y-axis
    ;;
  toggle-layout)
    layout=$(current_space_layout)
    case "$layout" in
      bsp) target="stack" ;;
      stack) target="bsp" ;;
      float) target="bsp" ;;
      *) target="bsp" ;;
    esac
    "$YABAI_BIN" -m space --layout "$target"
    ;;
  space-layout)
    layout=${1:-}
    if [[ -z "$layout" ]]; then
      echo "Usage: $0 space-layout <bsp|stack|float>" >&2
      exit 1
    fi
    "$YABAI_BIN" -m space --layout "$layout"
    ;;
  window-toggle-float)
    "$YABAI_BIN" -m window --toggle float
    ;;
  window-toggle-sticky)
    "$YABAI_BIN" -m window --toggle sticky
    ;;
  window-toggle-fullscreen)
    "$YABAI_BIN" -m window --toggle zoom-fullscreen
    ;;
  window-toggle-topmost)
    "$YABAI_BIN" -m window --toggle topmost
    ;;
  window-center)
    window_center
    ;;
  window-display-next)
    "$YABAI_BIN" -m window --display next
    ;;
  window-display-prev)
    "$YABAI_BIN" -m window --display prev
    ;;
  window-space-next)
    "$YABAI_BIN" -m window --space next
    ;;
  window-space-prev)
    "$YABAI_BIN" -m window --space prev
    ;;
  window-space)
    target=${1:-}
    if [[ -z "$target" ]]; then
      echo "Usage: $0 window-space <index>" >&2
      exit 1
    fi
    "$YABAI_BIN" -m window --space "$target"
    ;;
  space-focus-prev-wrap)
    space_focus_wrap prev
    ;;
  space-focus-next-wrap)
    space_focus_wrap next
    ;;
  space-prev)
    space_focus_safe prev
    ;;
  space-next)
    space_focus_safe next
    ;;
  space-recent)
    space_focus_safe recent
    ;;
  space-first)
    space_focus_safe first
    ;;
  space-last)
    space_focus_safe last
    ;;
  window-space-prev-wrap)
    window_space_wrap prev
    ;;
  window-space-next-wrap)
    window_space_wrap next
    ;;
  space-focus-app)
    space_focus_app "$@"
    ;;
  doctor)
    run_doctor
    ;;
  *)
    cat <<'USAGE'
Usage: yabai_control.sh <command>

Commands:
  status
  restart
  balance
  space-rotate|rotate
  mirror
  space-mirror-x|space-mirror-y
  toggle-layout
  space-layout <bsp|stack|float>
  window-toggle-float
  window-toggle-sticky
  window-toggle-fullscreen
  window-toggle-topmost
  window-center
  window-display-next|window-display-prev
  window-space-next|window-space-prev
  window-space <index>
  space-focus-prev-wrap|space-focus-next-wrap
  space-prev|space-next|space-recent|space-first|space-last
  window-space-prev-wrap|window-space-next-wrap
  space-focus-app <AppName>
  doctor
USAGE
    exit 1
    ;;
 esac
