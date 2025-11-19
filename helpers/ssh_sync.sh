#!/bin/bash
# SSH File Sync Helper
# Syncs files to/from remote servers

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"

action="${1:-help}"

get_sync_config() {
  if command -v jq &> /dev/null && [[ -f "$STATE_FILE" ]]; then
    local host=$(jq -r '.integrations.ssh_cloud.sync_host // empty' "$STATE_FILE" 2>/dev/null || echo "")
    local remote_path=$(jq -r '.integrations.ssh_cloud.sync_remote_path // empty' "$STATE_FILE" 2>/dev/null || echo "")
    local local_path=$(jq -r '.integrations.ssh_cloud.sync_local_path // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    echo "$host|$remote_path|$local_path"
  else
    echo "||"
  fi
}

sync_up() {
  IFS='|' read -r host remote_path local_path < <(get_sync_config)
  
  if [[ -z "$host" ]] || [[ -z "$remote_path" ]] || [[ -z "$local_path" ]]; then
    echo "Sync configuration not set. Please configure in state.json:"
    echo "  integrations.ssh_cloud.sync_host"
    echo "  integrations.ssh_cloud.sync_remote_path"
    echo "  integrations.ssh_cloud.sync_local_path"
    return 1
  fi
  
  echo "Syncing to $host:$remote_path..."
  rsync -avz --exclude '.git' --exclude 'build' --exclude 'bazel-*' \
    "$local_path/" "$host:$remote_path/"
  
  echo "✅ Sync complete"
}

sync_down() {
  IFS='|' read -r host remote_path local_path < <(get_sync_config)
  
  if [[ -z "$host" ]] || [[ -z "$remote_path" ]] || [[ -z "$local_path" ]]; then
    echo "Sync configuration not set. Please configure in state.json:"
    echo "  integrations.ssh_cloud.sync_host"
    echo "  integrations.ssh_cloud.sync_remote_path"
    echo "  integrations.ssh_cloud.sync_local_path"
    return 1
  fi
  
  echo "Syncing from $host:$remote_path..."
  rsync -avz --exclude '.git' --exclude 'build' --exclude 'bazel-*' \
    "$host:$remote_path/" "$local_path/"
  
  echo "✅ Sync complete"
}

case "$action" in
  up)
    sync_up
    ;;
  down)
    sync_down
    ;;
  help|*)
    echo "Usage: $0 {up|down}"
    echo ""
    echo "  up   - Sync local files to remote"
    echo "  down - Sync remote files to local"
    echo ""
    echo "Configure sync settings in state.json:"
    echo "  integrations.ssh_cloud.sync_host"
    echo "  integrations.ssh_cloud.sync_remote_path"
    echo "  integrations.ssh_cloud.sync_local_path"
    ;;
esac

