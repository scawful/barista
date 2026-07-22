#!/bin/bash

# Portable System Info event wrapper and native-failure fallback.
# Routine fallback updates only the compact CPU/memory anchor; detail probes
# and rows remain exclusive to the explicit popup_refresh action.

set -euo pipefail

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

# This plugin never consumes scripts_dir. Pre-seed it so the shared hover
# helpers do not read state.json before the row allowlist below can take over.
if [ -z "${SCRIPTS_DIR:-}" ]; then
  SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}/scripts}"
fi

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

ICON_CPU_OVERRIDE="${BARISTA_ICON_CPU:-}"
ICON_MEM_OVERRIDE="${BARISTA_ICON_MEM:-}"
ICON_DISK_OVERRIDE="${BARISTA_ICON_DISK:-}"
ICON_WIFI_OVERRIDE="${BARISTA_ICON_WIFI:-}"
ICON_WIFI_OFF_OVERRIDE="${BARISTA_ICON_WIFI_OFF:-}"
ICON_SWAP_OVERRIDE="${BARISTA_ICON_SWAP:-}"
ICON_UPTIME_OVERRIDE="${BARISTA_ICON_UPTIME:-}"
ACTION="${1:-}"
UPDATE_MAIN=1
SYSTEM_INFO_BIN="${SYSTEM_INFO_BIN:-$HOME/.config/sketchybar/bin/system_info_widget}"
SYSTEM_INFO_NATIVE_DISABLED=0
case "${BARISTA_SYSTEM_INFO_NATIVE_DISABLE:-0}" in
  1|true|TRUE|yes|YES|on|ON) SYSTEM_INFO_NATIVE_DISABLED=1 ;;
esac

if [ "$ACTION" = "popup_refresh" ]; then
  UPDATE_MAIN=0
fi

# Handle mouse events
case "${SENDER:-}" in
  "mouse.entered")
    highlight_with_timeout "$NAME" "background.drawing=on background.color=$HIGHLIGHT" "background.drawing=off"
    exit 0
    ;;
  "mouse.exited")
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set system_info popup.drawing=off
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
esac

if [ "$ACTION" != "popup_refresh" ] \
  && [ "$SYSTEM_INFO_NATIVE_DISABLED" -eq 0 ] \
  && [ -x "$SYSTEM_INFO_BIN" ]; then
  "$SYSTEM_INFO_BIN" && exit 0
fi

# Dynamic popup rows come from the exact allowlist supplied by the Lua layout.
# Older/portable callers can omit it and fall back to one state.json read.
CPU_ENABLED=0
MEM_ENABLED=1
DISK_ENABLED=1
NET_ENABLED=1
SWAP_ENABLED=1
UPTIME_ENABLED=1
PROCS_ENABLED=0

apply_row_allowlist() {
  local raw="${1:-}"
  local token seen
  case "$raw" in
    none)
      return 0
      ;;
    ""|,*|*,|*,,*)
      return 1
      ;;
  esac

  seen=","
  IFS=',' read -r -a row_tokens <<< "$raw"
  for token in "${row_tokens[@]}"; do
    case "$token" in
      cpu|mem|disk|net|swap|uptime|procs) ;;
      *) return 1 ;;
    esac
    case "$seen" in
      *",$token,"*) return 1 ;;
    esac
    seen="${seen}${token},"
    case "$token" in
      cpu) CPU_ENABLED=1 ;;
      mem) MEM_ENABLED=1 ;;
      disk) DISK_ENABLED=1 ;;
      net) NET_ENABLED=1 ;;
      swap) SWAP_ENABLED=1 ;;
      uptime) UPTIME_ENABLED=1 ;;
      procs) PROCS_ENABLED=1 ;;
    esac
  done
}

if [ "$UPDATE_MAIN" -eq 1 ]; then
  CPU_ENABLED=0
  MEM_ENABLED=0
  DISK_ENABLED=0
  NET_ENABLED=0
  SWAP_ENABLED=0
  UPTIME_ENABLED=0
  PROCS_ENABLED=0
elif [ "${BARISTA_SYSTEM_INFO_ROWS+x}" = "x" ]; then
  CPU_ENABLED=0
  MEM_ENABLED=0
  DISK_ENABLED=0
  NET_ENABLED=0
  SWAP_ENABLED=0
  UPTIME_ENABLED=0
  PROCS_ENABLED=0
  if ! apply_row_allowlist "$BARISTA_SYSTEM_INFO_ROWS"; then
    echo "Invalid BARISTA_SYSTEM_INFO_ROWS: $BARISTA_SYSTEM_INFO_ROWS" >&2
    exit 2
  fi
elif [ -f "$STATE_FILE" ]; then
  state_flags=""
  if command -v jq >/dev/null 2>&1; then
    state_flags=$(jq -r '
      (if type == "object" and (.system_info_items | type) == "object"
       then .system_info_items else {} end) as $items
      | [
          (if ($items | has("cpu")) then ($items.cpu == true) else false end),
          (if ($items | has("mem")) then ($items.mem == true) else true end),
          (if ($items | has("disk")) then ($items.disk == true) else true end),
          (if ($items | has("net")) then ($items.net == true) else true end),
          (if ($items | has("swap")) then ($items.swap == true) else true end),
          (if ($items | has("uptime")) then ($items.uptime == true) else true end),
          (if ($items | has("procs")) then ($items.procs == true) else false end)
        ]
      | map(if . then 1 else 0 end)
      | @tsv
    ' "$STATE_FILE" 2>/dev/null || true)
  elif command -v python3 >/dev/null 2>&1; then
    state_flags=$(python3 - "$STATE_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

items = data.get("system_info_items", {}) if isinstance(data, dict) else {}
if not isinstance(items, dict):
    items = {}
defaults = {
    "cpu": False,
    "mem": True,
    "disk": True,
    "net": True,
    "swap": True,
    "uptime": True,
    "procs": False,
}
print("\t".join(
    "1" if items.get(key, default) is True else "0"
    for key, default in defaults.items()
))
PY
)
  fi

  if [ -n "$state_flags" ]; then
    IFS=$'\t' read -r -a parsed_flags <<< "$state_flags"
    flags_valid=1
    if [ "${#parsed_flags[@]}" -ne 7 ]; then
      flags_valid=0
    else
      for flag in "${parsed_flags[@]}"; do
        case "$flag" in
          0|1) ;;
          *) flags_valid=0 ;;
        esac
      done
    fi
    if [ "$flags_valid" -eq 1 ]; then
      CPU_ENABLED="${parsed_flags[0]}"
      MEM_ENABLED="${parsed_flags[1]}"
      DISK_ENABLED="${parsed_flags[2]}"
      NET_ENABLED="${parsed_flags[3]}"
      SWAP_ENABLED="${parsed_flags[4]}"
      UPTIME_ENABLED="${parsed_flags[5]}"
      PROCS_ENABLED="${parsed_flags[6]}"
    fi
  fi
fi

if [ "$UPDATE_MAIN" -eq 0 ] \
  && [ "$CPU_ENABLED" -eq 0 ] \
  && [ "$MEM_ENABLED" -eq 0 ] \
  && [ "$DISK_ENABLED" -eq 0 ] \
  && [ "$NET_ENABLED" -eq 0 ] \
  && [ "$SWAP_ENABLED" -eq 0 ] \
  && [ "$UPTIME_ENABLED" -eq 0 ] \
  && [ "$PROCS_ENABLED" -eq 0 ]; then
  exit 0
fi

# Configuration
RED="${BARISTA_SYSTEM_INFO_RED:-0xfff38ba8}"
YELLOW="${BARISTA_SYSTEM_INFO_YELLOW:-0xfff9e2af}"
GREEN="${BARISTA_SYSTEM_INFO_GREEN:-0xffa6e3a1}"
BLUE="${BARISTA_SYSTEM_INFO_BLUE:-0xff89b4fa}"
TEAL="${BARISTA_SYSTEM_INFO_TEAL:-0xff94e2d5}"

# --- Statistics Gathering (OPTIMIZED) ---

# CPU: Use load average instead of expensive top command
# Load average is already computed by the kernel - instant access
cpu_load="0"
cpu_usage=0
if [ "$UPDATE_MAIN" -eq 1 ] || [ "$CPU_ENABLED" -eq 1 ] || [ "$PROCS_ENABLED" -eq 1 ]; then
  cpu_load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo 0)
  core_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  cpu_usage=$(awk -v l="$cpu_load" -v cores="$core_count" 'BEGIN {printf "%.0f", (l / cores) * 100}')
fi

# Memory: match the daemon-managed widget's active + wired + compressor model.
# Keep the displayed GiB values floored so portable routine and popup labels
# agree with the compiled widget manager.
mem_usage=0
used_mem=0
total_mem=0
mem_label="--/--"
if [ "$UPDATE_MAIN" -eq 1 ] || [ "$MEM_ENABLED" -eq 1 ]; then
  page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
  total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  vm_stats=$(vm_stat 2>/dev/null || true)
  read -r memory_stats_valid pages_active pages_wired pages_compressed < <(
    printf '%s\n' "$vm_stats" | awk '
      /^Pages active:/ {
        gsub(/\./, "", $NF)
        active = $NF
        active_found = 1
      }
      /^Pages wired down:/ {
        gsub(/\./, "", $NF)
        wired = $NF
        wired_found = 1
      }
      /^Pages occupied by compressor:/ {
        gsub(/\./, "", $NF)
        compressed = $NF
        compressed_found = 1
      }
      END {
        valid = active_found && wired_found && compressed_found
        printf "%d %.0f %.0f %.0f\n", valid, active + 0, wired + 0, compressed + 0
      }
    '
  )
  if [ "$memory_stats_valid" -eq 1 ] \
    && [ "$page_size" -gt 0 ] \
    && [ "$total_mem" -gt 0 ] 2>/dev/null; then
    used_pages=$(( pages_active + pages_wired + pages_compressed ))
    used_mem=$(( used_pages * page_size ))
    if [ "$used_mem" -gt "$total_mem" ]; then
      used_mem="$total_mem"
    fi
    mem_usage=$(( (used_mem * 100 + total_mem / 2) / total_mem ))
    gibibyte=$(( 1024 * 1024 * 1024 ))
    mem_used_gb=$(( used_mem / gibibyte ))
    mem_total_gb=$(( total_mem / gibibyte ))
    mem_label="${mem_used_gb}/${mem_total_gb}G"
  fi
fi

# Disk: prefer the writable Data volume on modern sealed-system macOS.
disk_usage=0
disk_label="--/--"
if [ "$UPDATE_MAIN" -eq 0 ] && [ "$DISK_ENABLED" -eq 1 ]; then
  disk_target="/"
  if [ -d "/System/Volumes/Data" ]; then
    disk_target="/System/Volumes/Data"
  fi
  disk_snapshot=$(df -h "$disk_target" 2>/dev/null || true)
  disk_usage=$(printf '%s\n' "$disk_snapshot" | awk 'NR==2 {print $5}' | tr -d '%')
  disk_label=$(printf '%s\n' "$disk_snapshot" | awk 'NR==2 {printf "%s/%s", $3, $2}')
  disk_usage="${disk_usage:-0}"
  if [ -z "$disk_label" ]; then
    disk_label="--/--"
  fi
fi

# Network: IP and SSID
resolve_wifi_interface() {
  if [ -n "${SKETCHYBAR_NET_INTERFACE:-}" ]; then
    printf '%s' "$SKETCHYBAR_NET_INTERFACE"
    return
  fi
  if command -v route >/dev/null 2>&1; then
    local iface
    iface=$(route -n get default 2>/dev/null | awk '/interface: / {print $2; exit}' || true)
    if [ -n "$iface" ]; then
      printf '%s' "$iface"
      return
    fi
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

wifi_interface=""
ip_address=""
ssid=""
if [ "$UPDATE_MAIN" -eq 0 ] && [ "$NET_ENABLED" -eq 1 ]; then
  wifi_interface=$(resolve_wifi_interface)
  ip_address=$(ipconfig getifaddr "$wifi_interface" 2>/dev/null || true)
  ssid=$(get_wifi_ssid "$wifi_interface")
fi

# Swap usage
swap_label="Swap: --"
if [ "$UPDATE_MAIN" -eq 0 ] && [ "$SWAP_ENABLED" -eq 1 ]; then
  swap_usage_raw=$(sysctl -n vm.swapusage 2>/dev/null || true)
  swap_used=$(echo "$swap_usage_raw" | awk -F'used = ' '{print $2}' | awk '{print $1}')
  swap_total=$(echo "$swap_usage_raw" | awk -F'total = ' '{print $2}' | awk '{print $1}')
  if [ -n "$swap_used" ] && [ -n "$swap_total" ]; then
    swap_label="Swap: ${swap_used}/${swap_total}"
  fi
fi

# Uptime (prefer sysctl for stability)
uptime_label="--"
if [ "$UPDATE_MAIN" -eq 0 ] && [ "$UPTIME_ENABLED" -eq 1 ]; then
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
if [ "$UPDATE_MAIN" -eq 1 ]; then
  cpu_icon="${ICON_CPU_OVERRIDE:-󰻠}"
  sketchybar --set system_info \
    icon="$cpu_icon" \
    label="${cpu_usage}% ${mem_label}" \
    icon.color="$cpu_status_color" \
    label.color="$cpu_status_color"
  exit 0
fi

if [ "$CPU_ENABLED" -eq 1 ]; then
  cpu_icon="${ICON_CPU_OVERRIDE:-󰻠}"
  sketchybar --set system_info.cpu \
    label="CPU Usage: ${cpu_usage}% (Load: ${cpu_load})" \
    icon="$cpu_icon" \
    icon.color="$cpu_status_color"
fi

if [ "$MEM_ENABLED" -eq 1 ]; then
  mem_icon="${ICON_MEM_OVERRIDE:-󰘚}"
  sketchybar --set system_info.mem \
    label="Memory: ${mem_label} (${mem_usage}%)" \
    icon="$mem_icon" \
    icon.color="$mem_status_color"
fi

if [ "$DISK_ENABLED" -eq 1 ]; then
  disk_icon="${ICON_DISK_OVERRIDE:-󰋊}"
  sketchybar --set system_info.disk \
    label="Disk Usage: ${disk_usage}% (${disk_label})" \
    icon="$disk_icon" \
    icon.color="$YELLOW"
fi

if [ "$NET_ENABLED" -eq 1 ]; then
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
fi

if [ "$SWAP_ENABLED" -eq 1 ]; then
  swap_icon="${ICON_SWAP_OVERRIDE:-󰾴}"
  sketchybar --set system_info.swap \
    label="$swap_label" \
    icon="$swap_icon" \
    icon.color="$BLUE"
fi

if [ "$UPTIME_ENABLED" -eq 1 ]; then
  uptime_icon="${ICON_UPTIME_OVERRIDE:-󰥔}"
  sketchybar --set system_info.uptime \
    label="Uptime: ${uptime_label}" \
    icon="$uptime_icon" \
    icon.color="$TEAL"
fi

if [ "$PROCS_ENABLED" -eq 1 ]; then
  top_line=""
  if ! IFS= read -r top_line < <(ps -Ar -o pcpu=,comm= 2>/dev/null); then
    top_line=""
  fi
  if [ -n "$top_line" ]; then
    read -r top_cpu top_path <<<"$top_line"
    top_name="${top_path##*/}"
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
