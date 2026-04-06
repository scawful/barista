#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
SKHD_BIN="${SKHD_BIN:-$(command -v skhd || true)}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
YABAI_LABEL="${BARISTA_YABAI_LABEL:-}"
YABAI_LABEL_NEW="com.asmvik.yabai"
YABAI_LABEL_OLD="com.koekeishiya.yabai"
SPACE_FOCUS_TIMEOUT_SEC="${SPACE_FOCUS_TIMEOUT_SEC:-1}"
SPACE_QUERY_TIMEOUT_SEC="${SPACE_QUERY_TIMEOUT_SEC:-1}"
SPACE_FOCUS_LOCK_STALE_SEC="${SPACE_FOCUS_LOCK_STALE_SEC:-2}"
SPACE_FOCUS_LOCK_DIR="/tmp/yabai_control_space_focus_${UID}.lock"
SPACE_FOCUS_OSASCRIPT_FALLBACK="${SPACE_FOCUS_OSASCRIPT_FALLBACK:-0}"

if [[ -z "$YABAI_BIN" ]]; then
  echo "yabai not found in PATH." >&2
  exit 1
fi

yabai_service_labels() {
  local labels=()
  if [[ -n "$YABAI_LABEL" ]]; then
    labels+=("$YABAI_LABEL")
  fi
  labels+=("$YABAI_LABEL_NEW" "$YABAI_LABEL_OLD")

  local seen=""
  local label
  for label in "${labels[@]}"; do
    [[ -z "$label" ]] && continue
    case " $seen " in
      *" $label "*) ;;
      *)
        seen="${seen:+$seen }$label"
        printf '%s\n' "$label"
        ;;
    esac
  done
}

yabai_has_service_file() {
  local label="$1"
  [[ -f "$HOME/Library/LaunchAgents/${label}.plist" ]]
}

yabai_launchctl_kickstart() {
  local label
  for label in $(yabai_service_labels); do
    if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1 || yabai_has_service_file "$label"; then
      if launchctl kickstart -kp "gui/${UID}/${label}" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done
  return 1
}

require_jq() {
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is required for this command." >&2
    exit 1
  fi
}

run_with_timeout() {
  local timeout_s="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_s" "$@"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_s" "$@"
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$timeout_s" "$@"
    return $?
  fi
  "$@"
}

acquire_space_focus_lock() {
  if mkdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null; then
    return 0
  fi

  local now mtime age
  now=$(date +%s)
  mtime=$(stat -f %m "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || echo 0)
  age=$(( now - mtime ))
  if (( age > SPACE_FOCUS_LOCK_STALE_SEC )); then
    rmdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || true
    mkdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null
    return $?
  fi
  return 1
}

release_space_focus_lock() {
  rmdir "$SPACE_FOCUS_LOCK_DIR" 2>/dev/null || true
}

current_space_index() {
  require_jq
  local current

  current=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows --window 2>/dev/null \
      | "$JQ_BIN" -r '.space // empty' \
      | head -n 1
  )
  if [[ -n "$current" && "$current" != "null" ]]; then
    echo "$current"
    return 0
  fi

  current=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display 2>/dev/null \
      | "$JQ_BIN" -r '.[] | select(.["has-focus"] == true or .["is-visible"] == true) | .index' \
      | head -n 1
  )
  if [[ -n "$current" && "$current" != "null" ]]; then
    echo "$current"
    return 0
  fi

  return 1
}

current_space_layout() {
  require_jq
  local layout

  layout=$(
    run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display 2>/dev/null \
      | "$JQ_BIN" -r '.[] | select(.["has-focus"] == true or .["is-visible"] == true) | .type' \
      | head -n 1
  )
  if [[ -n "$layout" && "$layout" != "null" ]]; then
    echo "$layout"
    return 0
  fi

  return 1
}

display_space_indices() {
  require_jq
  run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --spaces --display | "$JQ_BIN" -r '.[].index'
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
  if run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" "$YABAI_BIN" -m space --focus "$target" >/dev/null 2>&1; then
    return 0
  fi

  if space_focus_events_fallback "$direction"; then
    return 0
  fi

  echo "space focus failed (scripting addition likely missing)" >&2
  return 1
}

space_focus_events_fallback() {
  local direction="$1"
  if [[ "$SPACE_FOCUS_OSASCRIPT_FALLBACK" != "1" ]]; then
    return 1
  fi
  case "$direction" in
    next)
      run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" osascript -e 'tell application "System Events" to key code 124 using control down' >/dev/null 2>&1 || true
      return 0
      ;;
    prev)
      run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" osascript -e 'tell application "System Events" to key code 123 using control down' >/dev/null 2>&1 || true
      return 0
      ;;
  esac

  return 1
}

space_focus_wrap() {
  local direction="$1"
  if ! acquire_space_focus_lock; then
    # Drop repeated keypresses while a focus command is already in-flight.
    return 0
  fi

  local rc=0
  run_with_timeout "$SPACE_FOCUS_TIMEOUT_SEC" "$YABAI_BIN" -m space --focus "$direction" >/dev/null 2>&1 || rc=$?
  release_space_focus_lock

  if (( rc == 0 )); then
    return 0
  fi
  if (( rc == 124 )); then
    # Yabai focus command timed out; skip additional focus attempts for this press.
    return 0
  fi

  if space_focus_events_fallback "$direction"; then
    return 0
  fi

  echo "space focus failed (scripting addition likely missing)" >&2
  return 1
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
  space=$(run_with_timeout "$SPACE_QUERY_TIMEOUT_SEC" "$YABAI_BIN" -m query --windows | "$JQ_BIN" -r --arg app "$app" '.[] | select(.app == $app) | .space' | head -n 1)
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
  if yabai_launchctl_kickstart; then
    echo "yabai restarted via launchctl"
    return 0
  fi
  if "$YABAI_BIN" --install-service >/dev/null 2>&1; then
    if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
      echo "yabai restarted via installed service"
      return 0
    fi
  fi
  if command -v brew >/dev/null 2>&1; then
    if brew services restart yabai >/dev/null 2>&1; then
      echo "yabai restarted via brew"
      return 0
    fi
  fi
  start_yabai
}

start_yabai() {
  if pgrep -x yabai >/dev/null 2>&1; then
    echo "yabai already running"
    return 0
  fi
  if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
    echo "yabai started"
    return 0
  fi
  if "$YABAI_BIN" --install-service >/dev/null 2>&1; then
    if "$YABAI_BIN" --start-service >/dev/null 2>&1; then
      echo "yabai started via installed service"
      return 0
    fi
  fi
  if yabai_launchctl_kickstart; then
    echo "yabai started via launchctl"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    if brew services start yabai >/dev/null 2>&1; then
      echo "yabai started via brew"
      return 0
    fi
  fi
  echo "Unable to start yabai." >&2
  return 1
}

skhd_config_path() {
  if [[ -n "${SKHD_CONFIG:-}" ]]; then
    echo "$SKHD_CONFIG"
    return 0
  fi
  if [[ -f "$HOME/.config/skhd/skhdrc" ]]; then
    echo "$HOME/.config/skhd/skhdrc"
    return 0
  fi
  if [[ -f "$HOME/.skhdrc" ]]; then
    echo "$HOME/.skhdrc"
    return 0
  fi
  echo "$HOME/.config/skhd/skhdrc"
}

skhd_shortcuts_path() {
  echo "$HOME/.config/skhd/barista_shortcuts.conf"
}

skhd_expected_load_line() {
  printf '.load "%s"' "$(skhd_shortcuts_path)"
}

skhd_error_log() {
  local user
  user=$(id -un 2>/dev/null || echo "user")
  echo "/tmp/skhd_${user}.err.log"
}

skhd_error_recent() {
  local log="$1"
  local now
  local mtime
  now=$(date +%s)
  mtime=$(stat -f %m "$log" 2>/dev/null || echo 0)
  (( now - mtime < 3600 ))
}

skhd_running() {
  pgrep -x skhd >/dev/null 2>&1
}

skhd_pid_count() {
  local count
  count=$( (pgrep -x skhd 2>/dev/null || true) | wc -l | tr -d ' ' )
  echo "${count:-0}"
}

skhd_kill_all() {
  pkill -x skhd >/dev/null 2>&1 || true
}

skhd_start() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  if "$SKHD_BIN" --start-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services start skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

skhd_restart() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  if "$SKHD_BIN" --restart-service >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew services restart skhd >/dev/null 2>&1
    return 0
  fi
  return 1
}

skhd_reload() {
  if [[ -z "$SKHD_BIN" ]]; then
    return 1
  fi
  "$SKHD_BIN" --reload >/dev/null 2>&1
}

skhd_check_load_line() {
  local config="$1"
  if [[ ! -f "$config" ]]; then
    echo "skhd config not found: $config"
    return 1
  fi
  if grep -q "barista_shortcuts.conf" "$config"; then
    if grep -Eq '^[[:space:]]*\.load[[:space:]]+"[^"]*barista_shortcuts\.conf"' "$config"; then
      return 0
    fi
    echo "skhd config loads barista_shortcuts.conf without double quotes"
    return 2
  fi
  echo "skhd config missing .load for barista shortcuts"
  return 3
}

skhd_fix_load_line() {
  local config="$1"
  local expected
  expected=$(skhd_expected_load_line)
  mkdir -p "$(dirname "$config")" 2>/dev/null || true

  if [[ -f "$config" ]] && grep -q "barista_shortcuts.conf" "$config"; then
    local tmp
    tmp=$(mktemp)
    awk -v expected="$expected" '/barista_shortcuts\.conf/ { print expected; next } { print }' "$config" > "$tmp"
    mv "$tmp" "$config"
    return 0
  fi

  printf "\n%s\n" "$expected" >> "$config"
}

skhd_generate_shortcuts() {
  local generator="$CONFIG_DIR/helpers/generate_shortcuts.lua"
  if [[ ! -f "$generator" ]]; then
    echo "shortcuts generator not found: $generator" >&2
    return 1
  fi
  if ! command -v lua >/dev/null 2>&1; then
    echo "lua not found; cannot regenerate shortcuts" >&2
    return 1
  fi
  BARISTA_CONFIG_DIR="$CONFIG_DIR" lua "$generator" >/dev/null 2>&1
}

run_doctor() {
  local fix=0
  case "${1:-}" in
    fix|--fix) fix=1 ;;
  esac
  local ok=1
  if ! pgrep -x yabai >/dev/null 2>&1; then
    echo "yabai: not running"
    ok=0
    if (( fix == 1 )) && start_yabai; then
      sleep 0.5
      if pgrep -x yabai >/dev/null 2>&1; then
        echo "yabai: started"
        ok=1
      fi
    fi
  else
    echo "yabai: running"
  fi

  if [[ -z "$SKHD_BIN" ]]; then
    echo "skhd: not installed"
    ok=0
  else
    if ! skhd_running; then
      echo "skhd: not running"
      ok=0
      if (( fix == 1 )) && skhd_start; then
        echo "skhd: started"
      fi
    else
      echo "skhd: running"
    fi

    local pid_count
    pid_count=$(skhd_pid_count)
    if (( pid_count > 1 )); then
      echo "skhd: multiple instances (${pid_count})" >&2
      ok=0
      if (( fix == 1 )); then
        skhd_kill_all
        if skhd_start; then
          echo "skhd: restarted after duplicate cleanup"
        fi
      fi
    fi
  fi

  if [[ -n "$SKHD_BIN" ]]; then
    local skhd_config
    local skhd_shortcuts
    skhd_config=$(skhd_config_path)
    skhd_shortcuts=$(skhd_shortcuts_path)

    if [[ -f "$skhd_shortcuts" ]] && [[ -s "$skhd_shortcuts" ]]; then
      echo "skhd shortcuts: present"
    else
      echo "skhd shortcuts: missing ($skhd_shortcuts)" >&2
      ok=0
      if (( fix == 1 )) && skhd_generate_shortcuts; then
        echo "skhd shortcuts: regenerated"
      fi
    fi

    if skhd_check_load_line "$skhd_config"; then
      echo "skhd config: load ok"
    else
      ok=0
      if (( fix == 1 )); then
        skhd_fix_load_line "$skhd_config"
        echo "skhd config: load updated"
      fi
    fi

    local err_log
    err_log=$(skhd_error_log)
    if [[ -s "$err_log" ]] && skhd_error_recent "$err_log"; then
      echo "skhd warnings: recent log entries ($err_log)" >&2
      tail -n 3 "$err_log" | sed 's/^/  /' >&2 || true
      if (( fix == 1 )); then
        skhd_generate_shortcuts || true
        skhd_fix_load_line "$skhd_config" || true
      fi
    fi

    if (( fix == 1 )); then
      if skhd_running; then
        skhd_reload || skhd_restart || true
      else
        skhd_start || true
      fi
    fi
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
    layout=$(current_space_layout 2>/dev/null || echo "unknown")
    current=$(current_space_index 2>/dev/null || echo "unknown")
    echo "layout: $layout"
    echo "current space: $current"
    ;;
  start)
    start_yabai
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
    run_doctor "$@"
    ;;
  *)
    cat <<'USAGE'
Usage: yabai_control.sh <command>

Commands:
  status
  start
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
  doctor [--fix]
USAGE
    exit 1
    ;;
 esac
