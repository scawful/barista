#!/bin/bash
# C++ Project Switcher
# Lists and switches between C++ projects

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
PROJECT_PATH="${BARISTA_CODE_DIR:-$HOME/src}"

action="${1:-list}"

list_projects() {
  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "No projects directory found at $PROJECT_PATH"
    return
  fi
  
  echo "Available C++ Projects:"
  echo ""
  
  for project in "$PROJECT_PATH"/*; do
    if [[ -d "$project" ]]; then
      local name=$(basename "$project")
      local build_system=""
      
      if [[ -f "$project/BUILD.bazel" ]] || [[ -f "$project/WORKSPACE" ]]; then
        build_system="Bazel"
      elif [[ -f "$project/CMakeLists.txt" ]]; then
        build_system="CMake"
      elif [[ -f "$project/Makefile" ]]; then
        build_system="Make"
      fi
      
      if [[ -n "$build_system" ]]; then
        echo "  $name ($build_system)"
      fi
    fi
  done
}

switch_project() {
  local project_name="$1"
  
  if [[ -z "$project_name" ]]; then
    echo "Usage: $0 switch <project_name>"
    return 1
  fi
  
  local project_dir="$PROJECT_PATH/$project_name"
  
  if [[ ! -d "$project_dir" ]]; then
    echo "Project not found: $project_name"
    return 1
  fi
  
  # Detect build system
  local build_system="auto"
  if [[ -f "$project_dir/BUILD.bazel" ]] || [[ -f "$project_dir/WORKSPACE" ]]; then
    build_system="bazel"
  elif [[ -f "$project_dir/CMakeLists.txt" ]]; then
    build_system="cmake"
  elif [[ -f "$project_dir/Makefile" ]]; then
    build_system="make"
  fi
  
  # Update state.json
  if command -v jq &> /dev/null && [[ -f "$STATE_FILE" ]]; then
    jq \
      --arg project "$project_name" \
      --arg system "$build_system" \
      '.integrations.cpp_dev.current_project = $project | .integrations.cpp_dev.build_system = $system' \
      "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    
    echo "Switched to project: $project_name ($build_system)"
  else
    echo "jq not available or state.json not found"
    return 1
  fi
}

case "$action" in
  list)
    list_projects
    ;;
  switch)
    shift
    switch_project "$@"
    ;;
  *)
    echo "Usage: $0 {list|switch <project_name>}"
    exit 1
    ;;
esac
