#!/bin/bash

set -euo pipefail

MOUNTS_TOOL_DEFAULT="$HOME/src/tools/mounts/mounts"
MOUNTS_TOOL="${BARISTA_MOUNTS_TOOL:-$MOUNTS_TOOL_DEFAULT}"

TARGET_HOST="${BARISTA_MOUNT_HOST:-halext-nj}"
TARGET_PATH="${BARISTA_MOUNT_PATH:-/home/halext}"

print_usage() {
  cat <<'USAGE'
Usage: process_manager.sh <command>

Commands:
  top              Print top CPU process (pid cpu mem name)
  label            Print a short "Top CPU" label
  list             Print top 10 processes by CPU
  cleanup-mounts   Kill stale sshfs/macfuse mount processes (when not mounted)
USAGE
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

read_top_cpu() {
  ps -axo pid,pcpu,pmem,comm -r | awk 'NR==2 {print $1, $2, $3, $4}'
}

list_top_cpu() {
  ps -axo pid,pcpu,pmem,comm -r | head -n 11
}

cleanup_mounts() {
  local mounted=""
  if [ -x "$MOUNTS_TOOL" ]; then
    mounted=$("$MOUNTS_TOOL" status 2>/dev/null | awk '$2 == "mounted" {print $1}' | tr '\n' ' ' | sed 's/ $//')
  fi

  if [ -n "$mounted" ]; then
    echo "Mounts still active: $mounted" >&2
    echo "Skip cleanup to avoid interrupting active mounts." >&2
    return 1
  fi

  local sshfs_pids
  sshfs_pids=$(pgrep -f "sshfs ${TARGET_HOST}:${TARGET_PATH}" || true)
  if [ -n "$sshfs_pids" ]; then
    echo "$sshfs_pids" | xargs -n 1 kill -9 || true
    echo "Killed sshfs processes for ${TARGET_HOST}:${TARGET_PATH}."
  else
    echo "No sshfs processes found for ${TARGET_HOST}:${TARGET_PATH}."
  fi

  local macfuse_pids
  macfuse_pids=$(ps -axo pid,comm | awk '$2 == "(mount_macfuse)" {print $1}')
  if [ -n "$macfuse_pids" ]; then
    echo "$macfuse_pids" | xargs -n 1 kill -9 || true
    echo "Killed mount_macfuse processes (no mounts active)."
  else
    echo "No mount_macfuse processes found." 
  fi

  return 0
}

case "${1:-}" in
  top)
    read_top_cpu
    ;;
  label)
    if top_line=$(read_top_cpu); then
      if [ -n "$top_line" ]; then
        read -r pid cpu mem name <<<"$top_line"
        printf 'Top CPU: %s %s%%' "$name" "$cpu"
        exit 0
      fi
    fi
    echo "Top CPU: --"
    ;;
  list)
    list_top_cpu
    ;;
  cleanup-mounts|cleanup)
    cleanup_mounts
    ;;
  *)
    print_usage
    exit 1
    ;;
 esac
