#!/bin/bash

# System Info Widget - CPU, Mem, Disk, Net
# Designed for Barista - Clean, efficient system monitoring

set -euo pipefail

# Fallback binary usage if needed
SYSTEM_INFO_BIN="${SYSTEM_INFO_BIN:-$HOME/.config/sketchybar/bin/system_info_widget}"
if [ -x "$SYSTEM_INFO_BIN" ]; then
  exec "$SYSTEM_INFO_BIN"
fi

# Configuration
ICON_COLOR="0xffa6adc8"
LABEL_COLOR="0xffcdd6f4"
RED="0xfff38ba8"
YELLOW="0xfff9e2af"
GREEN="0xffa6e3a1"
BLUE="0xff89b4fa"

# Handle mouse events
if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set system_info popup.drawing=off
  exit 0
fi

# --- Statistics Gathering ---

# CPU: Top 1 sample, parse user+sys usage
cpu_usage=$(top -l 1 -n 0 | awk '/CPU usage/ {printf "%.0f", $3 + $5}')
cpu_load=$(sysctl -n vm.loadavg | awk '{print $2}')

# Memory: Wired + Active pages (approximate used) or use top's PhysMem
# Using vm_stat for speed if possible, otherwise top fallback
mem_usage=$(ps -A -o %mem | awk '{s+=$1} END {printf "%.0f", s}')

# Disk: Root usage
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
disk_label=$(df -h / | awk 'NR==2 {printf "%s/%s", $3, $2}')

# Network: IP and SSID
wifi_interface="${SKETCHYBAR_NET_INTERFACE:-en0}"
ip_address=$(ifconfig "$wifi_interface" 2>/dev/null | awk '/inet / {print $2}')
ssid=$(networksetup -getairportnetwork "$wifi_interface" 2>/dev/null | sed 's/Current Wi-Fi Network: //')

# --- Widget Logic ---

# CPU Status Color
cpu_status_color="$GREEN"
if [ "$cpu_usage" -gt 80 ]; then
  cpu_status_color="$RED"
elif [ "$cpu_usage" -gt 50 ]; then
  cpu_status_color="$YELLOW"
fi

# Main Widget Update
sketchybar --set system_info \
  icon="󰻠" \
  label="${cpu_usage}%" \
  icon.color="$cpu_status_color" \
  label.color="$LABEL_COLOR"

# Popup Items Update
sketchybar --set system_info.cpu \
  label="CPU Usage: ${cpu_usage}% (Load: ${cpu_load})" \
  icon="󰻠" \
  icon.color="$cpu_status_color"

sketchybar --set system_info.mem \
  label="Memory Usage: ${mem_usage}%" \
  icon="󰘚" \
  icon.color="$BLUE"

sketchybar --set system_info.disk \
  label="Disk Usage: ${disk_usage}% (${disk_label})" \
  icon="󰋊" \
  icon.color="$YELLOW"

if [ -n "$ip_address" ]; then
  sketchybar --set system_info.net \
    label="Wi-Fi: ${ssid} (${ip_address})" \
    icon="󰖩" \
    icon.color="$GREEN"
else
  sketchybar --set system_info.net \
    label="Wi-Fi: Disconnected" \
    icon="󰖪" \
    icon.color="$RED"
fi
