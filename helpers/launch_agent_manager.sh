#!/bin/bash
# Unified launch-agent helper for Barista/SketchyBar

set -euo pipefail

PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
DOMAIN="gui/$(id -u)"
AGENT_PID="-"
AGENT_STATUS="not_loaded"

if [[ $EUID -eq 0 ]]; then
  cat >&2 <<'ERR'
launch_agent_manager.sh should be run without sudo.
User LaunchAgents live in ~/Library/LaunchAgents and must be managed from the GUI domain (gui/$UID).
ERR
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: launch_agent_manager.sh <command> [args]

Commands:
  list [filter]       List LaunchAgents (JSON array). Optional substring filter by label.
  start <label>       Start or bootstrap the specified agent.
  stop <label>        Stop/bootout the specified agent.
  restart <label>     Stop then start the specified agent.
  status <label>      Print launchctl status for the agent.

Labels correspond to launchctl labels (e.g., homebrew.mxcl.sketchybar).
You may also pass the path to a specific plist under ~/Library/LaunchAgents.
EOF
}

die() {
  echo "launch_agent_manager: $*" >&2
  exit 1
}

get_label_from_plist() {
  local plist="$1"
  if [[ -f "$plist" ]]; then
    if label="$($PLIST_BUDDY -c 'Print :Label' "$plist" 2>/dev/null)"; then
      printf '%s\n' "$label"
      return 0
    fi
    local base
    base=$(basename "$plist")
    printf '%s\n' "${base%.plist}"
    return 0
  fi
  return 1
}

resolve_plist() {
  local target="$1"
  if [[ -z "$target" ]]; then
    return 1
  fi
  if [[ -f "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi
  local candidate="${PLIST_DIR}/${target}"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  local match=""
  while IFS= read -r -d '' plist; do
    local label
    label=$(get_label_from_plist "$plist") || continue
    if [[ "$label" == "$target" ]]; then
      match="$plist"
      break
    fi
  done < <(find "$PLIST_DIR" -maxdepth 1 -name "*.plist" -print0)
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
    return 0
  fi
  return 1
}

agent_state() {
  local label="$1"
  AGENT_PID="-"
  AGENT_STATUS="not_loaded"
  if [[ -z "$label" ]]; then
    return
  fi
  local info
  if ! info=$(launchctl list "$label" 2>/dev/null); then
    return
  fi
  AGENT_PID=$(printf '%s\n' "$info" | awk -F'= ' '/"PID"/ {gsub(/[^0-9]/,"",$2); if ($2=="") next; print $2; exit}')
  [[ -z "$AGENT_PID" ]] && AGENT_PID="-"
  AGENT_STATUS=$(printf '%s\n' "$info" | awk -F'= ' '/"LastExitStatus"/ {gsub(/[^0-9-]/,"",$2); if ($2=="") next; print $2; exit}')
  [[ -z "$AGENT_STATUS" ]] && AGENT_STATUS="0"
}

json_list() {
  local filter="${1:-}"
  local tmp
  tmp=$(mktemp)
  while IFS= read -r -d '' plist; do
    local label
    label=$(get_label_from_plist "$plist") || continue
    if [[ -n "$filter" && "$label" != *"$filter"* ]]; then
      continue
    fi
    agent_state "$label"
    printf '%s\t%s\t%s\t%s\n' "$label" "$plist" "$AGENT_PID" "$AGENT_STATUS" >>"$tmp"
  done < <(find "$PLIST_DIR" -maxdepth 1 -name "*.plist" -print0) || true

  python3 - "$tmp" <<'PY'
import json, sys, os
records = []
path = sys.argv[1]
with open(path, "r") as fh:
    for line in fh:
        label, plist, pid, status = line.rstrip("\n").split("\t")
        running = pid not in ("", "-")
        pid_value = None
        if running:
            try:
                pid_value = int(pid)
            except ValueError:
                running = False
        exit_status = None
        if status not in ("", "-", "not_loaded"):
            try:
                exit_status = int(status)
            except ValueError:
                exit_status = status
        records.append({
            "label": label,
            "plist": plist,
            "pid": pid_value,
            "running": running,
            "status": exit_status,
        })
json.dump(records, sys.stdout, indent=2)
PY
  rm -f "$tmp"
}

agent_loaded() {
  local label="$1"
  launchctl print "${DOMAIN}/${label}" >/dev/null 2>&1
}

start_agent() {
  local target="$1"
  [[ -z "$target" ]] && die "start requires a label or plist path"
  local plist
  plist=$(resolve_plist "$target") || die "unable to find plist for ${target}"
  local label
  label=$(get_label_from_plist "$plist") || die "unable to read label for ${plist}"
  if agent_loaded "$label"; then
    launchctl kickstart -kp "${DOMAIN}/${label}"
    echo "Restarted ${label} via kickstart."
  else
    launchctl bootstrap "$DOMAIN" "$plist"
    echo "Bootstrapped ${label} from ${plist}."
  fi
}

stop_agent() {
  local target="$1"
  [[ -z "$target" ]] && die "stop requires a label or plist path"
  local plist
  plist=$(resolve_plist "$target") || die "unable to find plist for ${target}"
  local label
  label=$(get_label_from_plist "$plist") || die "unable to read label for ${plist}"
  if agent_loaded "$label"; then
    launchctl bootout "${DOMAIN}/${label}"
    echo "Stopped ${label}."
  else
    echo "${label} is not loaded."
  fi
}

status_agent() {
  local target="$1"
  [[ -z "$target" ]] && die "status requires a label or plist path"
  local plist
  plist=$(resolve_plist "$target") || die "unable to find plist for ${target}"
  local label
  label=$(get_label_from_plist "$plist") || die "unable to read label for ${plist}"
  launchctl print "${DOMAIN}/${label}"
}

restart_agent() {
  local label="$1"
  stop_agent "$label" || true
  sleep 0.3
  start_agent "$label"
}

main() {
  local cmd="${1:-list}"
  shift || true
  case "$cmd" in
    list)
      json_list "${1:-}"
      ;;
    start)
      start_agent "${1:-}"
      ;;
    stop)
      stop_agent "${1:-}"
      ;;
    restart)
      restart_agent "${1:-}"
      ;;
    status)
      status_agent "${1:-}"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"

