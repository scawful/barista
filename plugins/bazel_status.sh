#!/bin/bash
# Bazel Build Status Widget
# Monitors Bazel build status for Google3 projects

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"

# Get Google3 project path
get_google3_path() {
  if command -v jq &> /dev/null && [[ -f "$STATE_FILE" ]]; then
    jq -r '.integrations.google_cpp.project_path // empty' "$STATE_FILE" 2>/dev/null || echo ""
  else
    echo "${HOME}/google3"
  fi
}

# Check Bazel status
check_bazel_status() {
  local project_path="$1"
  
  if [[ ! -d "$project_path" ]]; then
    echo "󰅖|No google3|0xFF0000"
    return
  fi
  
  # Check if Bazel server is running
  if pgrep -f "bazel.*server" > /dev/null; then
    echo "󰔟|Bazel Server|0x00FFFF"
    return
  fi
  
  # Check if build is in progress
  if pgrep -f "bazel build" > /dev/null; then
    echo "󰔟|Building...|0xFFFF00"
    return
  fi
  
  # Check if test is running
  if pgrep -f "bazel test" > /dev/null; then
    echo "󰈔|Testing...|0x00FF00"
    return
  fi
  
  # Check for bazel output directories
  if [[ -d "$project_path/bazel-bin" ]] || [[ -d "$project_path/bazel-out" ]]; then
    echo "󰄬|Ready|0x00FF00"
  else
    echo "󰅖|Not Built|0xFF8888"
  fi
}

# Main
main() {
  local project_path=$(get_google3_path)
  
  if [[ -z "$project_path" ]]; then
    project_path="${HOME}/google3"
  fi
  
  IFS='|' read -r icon label color < <(check_bazel_status "$project_path")
  
  sketchybar --set bazel_status \
    icon="$icon" \
    label="$label" \
    background.color="$color"
}

main "$@"

