#!/bin/bash
# C++ Build Status Widget
# Monitors build status for CMake, Bazel, or Make projects

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"

# Get current project and build system from state
get_project_config() {
  if command -v jq &> /dev/null && [[ -f "$STATE_FILE" ]]; then
    local project_path=$(jq -r '.integrations.cpp_dev.project_path // empty' "$STATE_FILE" 2>/dev/null || echo "")
    local current_project=$(jq -r '.integrations.cpp_dev.current_project // "default"' "$STATE_FILE" 2>/dev/null || echo "default")
    local build_system=$(jq -r '.integrations.cpp_dev.build_system // "auto"' "$STATE_FILE" 2>/dev/null || echo "auto")
    
    echo "$project_path|$current_project|$build_system"
  else
    echo "|default|auto"
  fi
}

# Detect build system
detect_build_system() {
  local project_dir="$1"
  
  if [[ -f "$project_dir/BUILD.bazel" ]] || [[ -f "$project_dir/WORKSPACE" ]]; then
    echo "bazel"
  elif [[ -f "$project_dir/CMakeLists.txt" ]]; then
    echo "cmake"
  elif [[ -f "$project_dir/Makefile" ]]; then
    echo "make"
  else
    echo "unknown"
  fi
}

# Check build status
check_build_status() {
  local project_dir="$1"
  local build_system="$2"
  
  if [[ ! -d "$project_dir" ]]; then
    echo "󰅖|No Project|0xFF0000"
    return
  fi
  
  case "$build_system" in
    bazel)
      if [[ -d "$project_dir/bazel-bin" ]] || [[ -d "$project_dir/bazel-out" ]]; then
        # Check if build is in progress
        if pgrep -f "bazel build" > /dev/null; then
          echo "󰔟|Building...|0xFFFF00"
        else
          echo "󰄬|Built|0x00FF00"
        fi
      else
        echo "󰅖|Not Built|0xFF8888"
      fi
      ;;
    cmake)
      if [[ -d "$project_dir/build" ]]; then
        if pgrep -f "cmake.*build" > /dev/null || pgrep -f "make" > /dev/null; then
          echo "󰔟|Building...|0xFFFF00"
        else
          echo "󰄬|Built|0x00FF00"
        fi
      else
        echo "󰅖|Not Built|0xFF8888"
      fi
      ;;
    make)
      if pgrep -f "make" > /dev/null; then
        echo "󰔟|Building...|0xFFFF00"
      elif [[ -f "$project_dir/Makefile" ]]; then
        echo "󰄬|Ready|0x00FF00"
      else
        echo "󰅖|No Makefile|0xFF8888"
      fi
      ;;
    *)
      echo "󰅖|Unknown|0xFF8888"
      ;;
  esac
}

# Main
main() {
  IFS='|' read -r project_path current_project build_system < <(get_project_config)
  
  if [[ -z "$project_path" ]]; then
    project_path="${BARISTA_CODE_DIR:-$HOME/src}"
  fi
  
  local full_path="$project_path/$current_project"
  
  if [[ "$build_system" == "auto" ]]; then
    build_system=$(detect_build_system "$full_path")
  fi
  
  IFS='|' read -r icon label color < <(check_build_status "$full_path" "$build_system")
  
  sketchybar --set cpp_build_status \
    icon="$icon" \
    label="$label ($build_system)" \
    background.color="$color"
}

main "$@"
