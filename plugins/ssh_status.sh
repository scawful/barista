#!/bin/bash
# SSH Connection Status Widget
# Monitors active SSH connections and cloud resources

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"
SSH_CONFIG="${HOME}/.ssh/config"

# Count active SSH connections
count_ssh_connections() {
  ps aux | grep -E "ssh\s+[^-]" | grep -v grep | wc -l | tr -d ' '
}

# Get SSH connection names from config
get_ssh_hosts() {
  if [[ -f "$SSH_CONFIG" ]]; then
    grep -E "^Host\s+" "$SSH_CONFIG" | awk '{print $2}' | grep -v "^\*$" | head -5
  fi
}

# Check if specific host is connected
is_host_connected() {
  local host="$1"
  ps aux | grep -E "ssh\s+.*$host" | grep -v grep > /dev/null
}

# Main
main() {
  local active_count=$(count_ssh_connections)
  
  if [[ "$active_count" -gt 0 ]]; then
    local hosts=$(get_ssh_hosts)
    local connected_hosts=""
    local count=0
    
    while IFS= read -r host; do
      if [[ -n "$host" ]] && is_host_connected "$host"; then
        if [[ -n "$connected_hosts" ]]; then
          connected_hosts="$connected_hosts, $host"
        else
          connected_hosts="$host"
        fi
        count=$((count + 1))
      fi
    done <<< "$hosts"
    
    if [[ "$count" -gt 0 ]]; then
      sketchybar --set ssh_connections \
        icon="󰆍" \
        label="$count active" \
        background.color="0x00FF00"
    else
      sketchybar --set ssh_connections \
        icon="󰆍" \
        label="$active_count active" \
        background.color="0xFFFF00"
    fi
  else
    sketchybar --set ssh_connections \
      icon="󰆍" \
      label="Disconnected" \
      background.color="0xFF8888"
  fi
}

main "$@"

