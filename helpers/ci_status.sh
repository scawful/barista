#!/bin/bash
# CI/CD Status Checker
# Checks CI/CD status for Google projects

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"

action="${1:-show}"

get_ci_config() {
  if command -v jq &> /dev/null && [[ -f "$STATE_FILE" ]]; then
    local ci_url=$(jq -r '.integrations.google_cpp.ci_url // empty' "$STATE_FILE" 2>/dev/null || echo "")
    local project_id=$(jq -r '.integrations.google_cpp.ci_project_id // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    echo "$ci_url|$project_id"
  else
    echo "||"
  fi
}

show_status() {
  IFS='|' read -r ci_url project_id < <(get_ci_config)
  
  if [[ -z "$ci_url" ]]; then
    echo "CI/CD not configured. Set integrations.google_cpp.ci_url in state.json"
    return 1
  fi
  
  echo "Opening CI/CD status..."
  
  if [[ -n "$project_id" ]]; then
    open -a "Google Chrome" "$ci_url/$project_id"
  else
    open -a "Google Chrome" "$ci_url"
  fi
}

case "$action" in
  show)
    show_status
    ;;
  *)
    echo "Usage: $0 show"
    ;;
esac

