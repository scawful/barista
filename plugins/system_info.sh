#!/bin/bash

# System Info Widget - CPU, Mem, Disk, Net
# Designed for Barista - Clean, efficient system monitoring
# OPTIMIZED: Replaced slow top command with sysctl/vm_stat

set -euo pipefail

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

ICON_CPU_OVERRIDE="${BARISTA_ICON_CPU:-}"
ICON_MEM_OVERRIDE="${BARISTA_ICON_MEM:-}"
ICON_DISK_OVERRIDE="${BARISTA_ICON_DISK:-}"
ICON_WIFI_OVERRIDE="${BARISTA_ICON_WIFI:-}"
ICON_WIFI_OFF_OVERRIDE="${BARISTA_ICON_WIFI_OFF:-}"
ICON_SWAP_OVERRIDE="${BARISTA_ICON_SWAP:-}"
ICON_UPTIME_OVERRIDE="${BARISTA_ICON_UPTIME:-}"

# Handle mouse events
case "${SENDER:-}" in
  "mouse.entered")
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set system_info popup.drawing=off
    exit 0
    ;;
esac

# Detect whether CPU row is enabled (default to off unless explicitly enabled)
CPU_ENABLED=0
PROCS_ENABLED=0
if [ -f "$STATE_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    cpu_flag=$(jq -r '.system_info_items.cpu // false' "$STATE_FILE" 2>/dev/null || echo false)
    if [ "$cpu_flag" = "true" ]; then
      CPU_ENABLED=1
    fi
    procs_flag=$(jq -r '.system_info_items.procs // false' "$STATE_FILE" 2>/dev/null || echo false)
    if [ "$procs_flag" = "true" ]; then
      PROCS_ENABLED=1
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
    procs_flag=$(python3 - <<'PY' "$STATE_FILE"
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

value = data.get("system_info_items", {}).get("procs", False)
print("true" if value else "false")
PY
)
    if [ "$procs_flag" = "true" ]; then
      PROCS_ENABLED=1
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
TEAL="0xff94e2d5"

# --- Statistics Gathering (OPTIMIZED) ---

# CPU: Use load average instead of expensive top command
# Load average is already computed by the kernel - instant access
cpu_load=$(sysctl -n vm.loadavg | awk '{print $2}')
# Convert load to rough percentage (assuming typical 8-core machine)
core_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
cpu_usage=$(awk -v l="$cpu_load" -v cores="$core_count" 'BEGIN {printf "%.0f", (l / cores) * 100}')

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

if [ "$total_mem" -gt 0 ]; then
  mem_used_gb=$(awk -v used="$used_mem" 'BEGIN {printf "%.0f", used / 1024 / 1024 / 1024}')
  mem_total_gb=$(awk -v total="$total_mem" 'BEGIN {printf "%.0f", total / 1024 / 1024 / 1024}')
  mem_label="${mem_used_gb}/${mem_total_gb}G"
else
  mem_label="--/--"
fi

# Disk: Root usage
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
disk_label=$(df -h / | awk 'NR==2 {printf "%s/%s", $3, $2}')

# Network: IP and SSID
resolve_wifi_interface() {
  if [ -n "${SKETCHYBAR_NET_INTERFACE:-}" ]; then
    printf '%s' "$SKETCHYBAR_NET_INTERFACE"
    return
  fi
  if command -v networksetup >/dev/null 2>&1; then
    local iface
    iface=$(networksetup -listallhardwareports 2>/dev/null | awk '
      $0 ~ /^Hardware Port: (Wi-Fi|AirPort)$/ {found=1}
      found && $0 ~ /^Device: / {print $2; exit}
    ' || true)
    if [ -n "$iface" ]; then
      printf '%s' "$iface"
      return
    fi
  fi
  if command -v route >/dev/null 2>&1; then
    local iface
    iface=$(route -n get default 2>/dev/null | awk '/interface: / {print $2; exit}' || true)
    if [ -n "$iface" ]; then
      printf '%s' "$iface"
      return
    fi
  fi
  printf '%s' "en0"
}

get_wifi_ssid() {
  local iface="$1"
  local ssid=""
  local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
  if [ -x "$airport" ]; then
    ssid=$("$airport" -I 2>/dev/null | awk -F': ' '/ SSID/ {print $2; exit}' || true)
  fi
  if [ -z "$ssid" ] && command -v networksetup >/dev/null 2>&1; then
    ssid=$(networksetup -getairportnetwork "$iface" 2>/dev/null | awk -F': ' '/Current Wi-Fi Network:/{print $2; exit}' || true)
  fi
  if [ "$ssid" = "You are not associated with an AirPort network." ]; then
    ssid=""
  fi
  printf '%s' "$ssid"
}

wifi_interface=$(resolve_wifi_interface)
ip_address=$(ipconfig getifaddr "$wifi_interface" 2>/dev/null || true)
ssid=$(get_wifi_ssid "$wifi_interface")

# Swap usage
swap_usage_raw=$(sysctl -n vm.swapusage 2>/dev/null || true)
swap_used=$(echo "$swap_usage_raw" | awk -F'used = ' '{print $2}' | awk '{print $1}')
swap_total=$(echo "$swap_usage_raw" | awk -F'total = ' '{print $2}' | awk '{print $1}')
if [ -n "$swap_used" ] && [ -n "$swap_total" ]; then
  swap_label="Swap: ${swap_used}/${swap_total}"
else
  swap_label="Swap: --"
fi

# Uptime (prefer sysctl for stability)
if command -v python3 >/dev/null 2>&1; then
  uptime_label=$(python3 - <<'PY'
import re
import time
import subprocess

raw = subprocess.check_output(["sysctl", "-n", "kern.boottime"], text=True).strip()
match = re.search(r"sec = (\d+)", raw)
if not match:
    print("--")
    raise SystemExit(0)
boot = int(match.group(1))
delta = max(0, int(time.time()) - boot)
days, rem = divmod(delta, 86400)
hours, rem = divmod(rem, 3600)
minutes, _ = divmod(rem, 60)
parts = []
if days:
    parts.append(f"{days}d")
if hours or days:
    parts.append(f"{hours}h")
parts.append(f"{minutes}m")
print(" ".join(parts))
PY
)
else
  uptime_label=$(uptime | sed -E 's/^.*up ([^,]+).*/\1/' | sed 's/^ *//')
fi

# --- Widget Logic ---

# CPU Status Color
cpu_status_color="$GREEN"
if [ "$cpu_usage" -gt 80 ]; then
  cpu_status_color="$RED"
elif [ "$cpu_usage" -gt 50 ]; then
  cpu_status_color="$YELLOW"
fi

mem_status_color="$GREEN"
if [ "$mem_usage" -gt 80 ]; then
  mem_status_color="$RED"
elif [ "$mem_usage" -gt 60 ]; then
  mem_status_color="$YELLOW"
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
    label="${mem_label}" \
    icon.color="$mem_status_color" \
    label.color="$mem_status_color"
fi

mem_icon="${ICON_MEM_OVERRIDE:-󰘚}"
sketchybar --set system_info.mem \
  label="Memory: ${mem_label} (${mem_usage}%)" \
  icon="$mem_icon" \
  icon.color="$mem_status_color"

disk_icon="${ICON_DISK_OVERRIDE:-󰋊}"
sketchybar --set system_info.disk \
  label="Disk Usage: ${disk_usage}% (${disk_label})" \
  icon="$disk_icon" \
  icon.color="$YELLOW"

wifi_icon="${ICON_WIFI_OVERRIDE:-󰖩}"
wifi_off_icon="${ICON_WIFI_OFF_OVERRIDE:-󰖪}"
if [ -n "$ssid" ]; then
  local_label="Wi-Fi: ${ssid}"
  if [ -n "$ip_address" ]; then
    local_label="${local_label} (${ip_address})"
  fi
  sketchybar --set system_info.net \
    label="$local_label" \
    icon="$wifi_icon" \
    icon.color="$GREEN"
elif [ -n "$ip_address" ]; then
  sketchybar --set system_info.net \
    label="Network: ${ip_address}" \
    icon="$wifi_icon" \
    icon.color="$GREEN"
else
  sketchybar --set system_info.net \
    label="Wi-Fi: Disconnected" \
    icon="$wifi_off_icon" \
    icon.color="$RED"
fi

swap_icon="${ICON_SWAP_OVERRIDE:-󰾴}"
sketchybar --set system_info.swap \
  label="$swap_label" \
  icon="$swap_icon" \
  icon.color="$BLUE"

uptime_icon="${ICON_UPTIME_OVERRIDE:-󰥔}"
sketchybar --set system_info.uptime \
  label="Uptime: ${uptime_label}" \
  icon="$uptime_icon" \
  icon.color="$TEAL"

if [ "$PROCS_ENABLED" -eq 1 ]; then
  top_line=$(ps -axo pid,pcpu,pmem,comm -r | awk 'NR==2 {print $1, $2, $3, $4}')
  if [ -n "$top_line" ]; then
    read -r top_pid top_cpu top_mem top_name <<<"$top_line"
    procs_label="Top CPU: ${top_name} ${top_cpu}%"
  else
    procs_label="Top CPU: --"
  fi
  procs_icon="${ICON_CPU_OVERRIDE:-󰻠}"
  sketchybar --set system_info.procs \
    label="$procs_label" \
    icon="$procs_icon" \
    icon.color="$cpu_status_color"
fi
