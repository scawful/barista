#!/bin/bash

# System Info Widget - CPU, Mem, Disk, Net
# Designed for Barista - Clean, efficient system monitoring
# OPTIMIZED: Replaced slow top command with sysctl/vm_stat

set -euo pipefail

HIGHLIGHT="0x40f5c2e7"
ICON_CPU_OVERRIDE="${BARISTA_ICON_CPU:-}"
ICON_MEM_OVERRIDE="${BARISTA_ICON_MEM:-}"
ICON_DISK_OVERRIDE="${BARISTA_ICON_DISK:-}"
ICON_WIFI_OVERRIDE="${BARISTA_ICON_WIFI:-}"
ICON_WIFI_OFF_OVERRIDE="${BARISTA_ICON_WIFI_OFF:-}"

# Handle mouse events
case "${SENDER:-}" in
  "mouse.entered")
    sketchybar --set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    sketchybar --set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set system_info popup.drawing=off
    exit 0
    ;;
esac

# Detect whether CPU row is enabled (default to off unless explicitly enabled)
CPU_ENABLED=0
STATE_FILE="$HOME/.config/sketchybar/state.json"
if [ -f "$STATE_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    cpu_flag=$(jq -r '.system_info_items.cpu // false' "$STATE_FILE" 2>/dev/null || echo false)
    if [ "$cpu_flag" = "true" ]; then
      CPU_ENABLED=1
    fi
  elif command -v python3 >/dev/null 2>&1; then
    cpu_flag=$(python3 - <<'PY' "$STATE_FILE"
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

value = data.get("system_info_items", {}).get("cpu", False)
print("true" if value else "false")
PY
)
    if [ "$cpu_flag" = "true" ]; then
      CPU_ENABLED=1
    fi
  fi
fi

# Fallback binary usage if needed (only when CPU row is enabled)
SYSTEM_INFO_BIN="${SYSTEM_INFO_BIN:-$HOME/.config/sketchybar/bin/system_info_widget}"
if [ "$CPU_ENABLED" -eq 1 ] && [ -x "$SYSTEM_INFO_BIN" ]; then
  exec "$SYSTEM_INFO_BIN"
fi

# Configuration
ICON_COLOR="0xffa6adc8"
LABEL_COLOR="0xffcdd6f4"
RED="0xfff38ba8"
YELLOW="0xfff9e2af"
GREEN="0xffa6e3a1"
BLUE="0xff89b4fa"

# --- Statistics Gathering (OPTIMIZED) ---

# CPU: Use load average instead of expensive top command
# Load average is already computed by the kernel - instant access
cpu_load=$(sysctl -n vm.loadavg | awk '{print $2}')
# Convert load to rough percentage (assuming typical 8-core machine)
core_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
cpu_usage=$(awk -v load="$cpu_load" -v cores="$core_count" 'BEGIN {printf "%.0f", (load / cores) * 100}')

# Memory: Use vm_stat (instant kernel stats) instead of slow ps -A
# Calculate used memory percentage from vm_stat pages
page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
vm_stats=$(vm_stat 2>/dev/null)
pages_active=$(echo "$vm_stats" | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
pages_wired=$(echo "$vm_stats" | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')
pages_compressed=$(echo "$vm_stats" | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}')
used_mem=$(( (${pages_active:-0} + ${pages_wired:-0} + ${pages_compressed:-0}) * page_size ))
if [ "$total_mem" -gt 0 ]; then
  mem_usage=$(awk -v used="$used_mem" -v total="$total_mem" 'BEGIN {printf "%.0f", (used / total) * 100}')
else
  mem_usage=0
fi

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
if [ "$CPU_ENABLED" -eq 1 ]; then
  cpu_icon="${ICON_CPU_OVERRIDE:-󰻠}"
  sketchybar --set system_info \
    icon="$cpu_icon" \
    label="${cpu_usage}%" \
    icon.color="$cpu_status_color" \
    label.color="$cpu_status_color"

  # Popup Items Update
  sketchybar --set system_info.cpu \
    label="CPU Usage: ${cpu_usage}% (Load: ${cpu_load})" \
    icon="$cpu_icon" \
    icon.color="$cpu_status_color"
else
  mem_icon="${ICON_MEM_OVERRIDE:-󰘚}"
  sketchybar --set system_info \
    icon="$mem_icon" \
    label="${mem_usage}%" \
    icon.color="$BLUE" \
    label.color="$BLUE"
fi

mem_icon="${ICON_MEM_OVERRIDE:-󰘚}"
sketchybar --set system_info.mem \
  label="Memory Usage: ${mem_usage}%" \
  icon="$mem_icon" \
  icon.color="$BLUE"

disk_icon="${ICON_DISK_OVERRIDE:-󰋊}"
sketchybar --set system_info.disk \
  label="Disk Usage: ${disk_usage}% (${disk_label})" \
  icon="$disk_icon" \
  icon.color="$YELLOW"

wifi_icon="${ICON_WIFI_OVERRIDE:-󰖩}"
wifi_off_icon="${ICON_WIFI_OFF_OVERRIDE:-󰖪}"
if [ -n "$ip_address" ]; then
  sketchybar --set system_info.net \
    label="Wi-Fi: ${ssid} (${ip_address})" \
    icon="$wifi_icon" \
    icon.color="$GREEN"
else
  sketchybar --set system_info.net \
    label="Wi-Fi: Disconnected" \
    icon="$wifi_off_icon" \
    icon.color="$RED"
fi
