#!/bin/bash

# Modern System Info - Icons and clean formatting

SYSTEM_INFO_BIN="${SYSTEM_INFO_BIN:-$HOME/.config/sketchybar/bin/system_info_widget}"
if [ -x "$SYSTEM_INFO_BIN" ]; then
  exec "$SYSTEM_INFO_BIN"
fi

set -euo pipefail

if [ "${SENDER:-}" = "mouse.exited.global" ]; then
  sketchybar --set system_info popup.drawing=off
  exit 0
fi

# Get system stats
top_snapshot="$(top -l 1 -n 0)"

# CPU usage with color coding
cpu_used=$(printf '%s\n' "$top_snapshot" | awk '
  /CPU usage/ {
    u=$3; gsub("[^0-9.]", "", u);
    s=$5; gsub("[^0-9.]", "", s);
    printf "%.0f", u + s;
    exit
  }
')

# Memory info
physmem_line=$(printf '%s\n' "$top_snapshot" | awk '/PhysMem/ {sub("PhysMem: ",""); print; exit}')
if [ -z "$physmem_line" ]; then
  physmem_line="unavailable"
fi

# Parse memory for better display
mem_used=$(echo "$physmem_line" | awk '{print $1}')
mem_wired=$(echo "$physmem_line" | grep -o '[0-9.]*[KMGT] wired' | awk '{print $1}')

# Disk info
disk_line=$(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')

# Network info
wifi_interface="${SKETCHYBAR_NET_INTERFACE:-en0}"
net_info=$(ifconfig "$wifi_interface" 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')
wifi_ssid=$(networksetup -getairportnetwork "$wifi_interface" 2>/dev/null | sed 's/Current Wi-Fi Network: //')

# Load average
load_avg=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')

# Battery info (if available)
battery_percent=$(pmset -g batt | grep -o '[0-9]*%' | tr -d '%')
battery_charging=$(pmset -g batt | grep -q 'AC Power' && echo "⚡" || echo "")

# Uptime
uptime_days=$(uptime | awk '{print $3}' | tr -d ',')

# Defaults for missing values
if [ -z "$cpu_used" ]; then cpu_used="0"; fi
if [ -z "$disk_line" ]; then disk_line="n/a"; fi
if [ -z "$net_info" ]; then net_info="offline"; fi
if [ -z "$load_avg" ]; then load_avg="0.00"; fi

# CPU color based on load (single icon, color changes)
cpu_icon="󰻠"  # Single consistent CPU icon
cpu_color="0xFFa6e3a1"  # Green
if [ "${cpu_used%%.*}" -gt 80 ]; then
  cpu_color="0xFFf38ba8"  # Red for high load
elif [ "${cpu_used%%.*}" -gt 50 ]; then
  cpu_color="0xFFfab387"  # Peach for medium load
fi

# Main widget summary - clean percentage only
summary="${cpu_used}%"

# Update main widget with color
sketchybar --set system_info \
  icon="$cpu_icon" \
  label="$summary" \
  icon.color="$cpu_color" \
  label.font.style="Semibold"

# Update popup items with clean labels (no duplicate icons)
sketchybar --set system_info.cpu \
  label="CPU ${cpu_used}%    Load ${load_avg}"

sketchybar --set system_info.mem \
  label="Memory ${mem_used}"

sketchybar --set system_info.disk \
  label="Disk ${disk_line}"

# Network with better formatting and color
if [ "$net_info" = "offline" ]; then
  sketchybar --set system_info.net \
    label="Wi-Fi Offline" \
    icon.color="0xFFf38ba8"
else
  if [ -n "$wifi_ssid" ]; then
    wifi_label="Wi-Fi ${wifi_ssid} (${net_info})"
  else
    wifi_label="Wi-Fi ${net_info}"
  fi
  sketchybar --set system_info.net \
    label="$wifi_label" \
    icon.color="0xFFa6e3a1"
fi
