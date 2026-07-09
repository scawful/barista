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
  load             Print compact current load and Barista process summary
  barista          Print Barista-related process family
  runaways         Flag hot/stale Barista plugin processes
  cleanup-runaways Dry-run targeted cleanup; pass --yes to kill flagged PIDs
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

process_snapshot() {
  if [ -n "${BARISTA_PROCESS_SNAPSHOT:-}" ] && [ -f "$BARISTA_PROCESS_SNAPSHOT" ]; then
    cat "$BARISTA_PROCESS_SNAPSHOT"
    return
  fi
  ps -axo pid=,ppid=,pcpu=,pmem=,etime=,state=,command= 2>/dev/null
}

barista_process_pattern='sketchybar|SketchyBar|yabai|skhd|widget_manager daemon|runtime_context|sketchybarrc|plugins/space.sh|plugins/space_visuals.sh|plugins/refresh_spaces.sh'

barista_processes() {
  printf '%-7s %-7s %-6s %-6s %-12s %-5s %s\n' PID PPID CPU MEM ELAPSED STATE COMMAND
  process_snapshot | awk -v patterns="$barista_process_pattern" '
    BEGIN { split(patterns, p, /\|/) }
    {
      pid=$1; ppid=$2; cpu=$3; mem=$4; elapsed=$5; state=$6
      command=$0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", command)
      matched=0
      for (i in p) {
        if (index(command, p[i]) > 0) {
          matched=1
          break
        }
      }
      if (matched && index(command, "process_manager.sh") == 0) {
        printf "%-7s %-7s %-6s %-6s %-12s %-5s %s\n", pid, ppid, cpu, mem, elapsed, state, command
      }
    }
  '
}

top_process_snapshot() {
  local command_width="${BARISTA_LOAD_COMMAND_WIDTH:-140}"
  process_snapshot | awk -v command_width="$command_width" '
    function command_from_line(line) {
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", line)
      return line
    }
    function compact_command(command) {
      if (command_width > 0 && length(command) > command_width) {
        return substr(command, 1, command_width - 3) "..."
      }
      return command
    }
    {
      cpu=$3 + 0
      if (NR == 1 || cpu > max_cpu) {
        max_cpu=cpu
        max_pid=$1
        max_mem=$4 + 0
        max_command=command_from_line($0)
      }
    }
    END {
      if (max_pid != "") {
        printf "Top: pid=%s cpu=%.1f%% mem=%.1f%% command=%s\n", max_pid, max_cpu, max_mem, compact_command(max_command)
      } else {
        print "Top: --"
      }
    }
  '
}

barista_load_summary() {
  process_snapshot | awk -v patterns="$barista_process_pattern" '
    BEGIN { split(patterns, p, /\|/) }
    function command_from_line(line) {
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", line)
      return line
    }
    {
      command=command_from_line($0)
      matched=0
      for (i in p) {
        if (index(command, p[i]) > 0) {
          matched=1
          break
        }
      }
      if (matched && index(command, "process_manager.sh") == 0) {
        count++
        cpu += $3 + 0
        mem += $4 + 0
      }
    }
    END {
      printf "Barista: processes=%d cpu=%.1f%% mem=%.1f%%\n", count + 0, cpu + 0, mem + 0
    }
  '
}

load_snapshot() {
  local runaway_output runaway_count
  echo "Load snapshot"
  if command_exists uptime; then
    uptime | sed 's/^[[:space:]]*/System: /'
  fi
  top_process_snapshot
  barista_load_summary
  runaway_output="$(runaway_candidates)"
  if [ -n "$runaway_output" ]; then
    runaway_count="$(printf '%s\n' "$runaway_output" | awk 'END {print NR + 0}')"
    printf 'Runaways: %s flagged\n' "$runaway_count"
    printf '%s\n' "$runaway_output" | sed 's/^/  /'
  else
    echo "Runaways: none"
  fi
}

runaway_candidates() {
  local cpu_threshold="${BARISTA_RUNAWAY_CPU_THRESHOLD:-25}"
  local count_threshold="${BARISTA_RUNAWAY_COUNT_THRESHOLD:-3}"
  local age_seconds="${BARISTA_RUNAWAY_AGE_SECONDS:-30}"
  local age_cpu_threshold="${BARISTA_RUNAWAY_AGE_CPU_THRESHOLD:-5}"

  process_snapshot | awk \
    -v cpu_threshold="$cpu_threshold" \
    -v count_threshold="$count_threshold" \
    -v age_seconds="$age_seconds" \
    -v age_cpu_threshold="$age_cpu_threshold" '
    function elapsed_seconds(raw, parts, hms, days, h, m, s, n) {
      days=0
      if (raw ~ /-/) {
        split(raw, parts, "-")
        days=parts[1] + 0
        raw=parts[2]
      }
      n=split(raw, hms, ":")
      if (n == 3) {
        h=hms[1] + 0; m=hms[2] + 0; s=hms[3] + 0
      } else if (n == 2) {
        h=0; m=hms[1] + 0; s=hms[2] + 0
      } else {
        h=0; m=0; s=raw + 0
      }
      return days * 86400 + h * 3600 + m * 60 + s
    }
    function command_from_line(line) {
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", line)
      return line
    }
    {
      pid=$1; cpu=$3 + 0; elapsed=$5
      command=command_from_line($0)
      is_plugin=(index(command, "plugins/space.sh") || index(command, "plugins/space_visuals.sh") || index(command, "plugins/refresh_spaces.sh"))
      if (index(command, "plugins/space.sh")) {
        space_count++
        space_pids = space_pids (space_pids == "" ? "" : " ") pid
      }
      if (is_plugin && cpu >= cpu_threshold) {
        printf "RUNAWAY cpu pid=%s cpu=%.1f elapsed=%s command=%s\n", pid, cpu, elapsed, command
      } else if (is_plugin && cpu >= age_cpu_threshold && elapsed_seconds(elapsed) >= age_seconds) {
        printf "RUNAWAY age_cpu pid=%s cpu=%.1f elapsed=%s command=%s\n", pid, cpu, elapsed, command
      }
    }
    END {
      if (space_count > count_threshold) {
        printf "RUNAWAY count kind=space.sh count=%d threshold=%d pids=%s\n", space_count, count_threshold, space_pids
      }
    }
  '
}

runaways() {
  local output
  output="$(runaway_candidates)"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  else
    echo "No Barista runaways detected."
  fi
}

cleanup_runaways() {
  local confirm="${1:-}"
  local candidates pids
  candidates="$(runaway_candidates)"
  if [ -z "$candidates" ]; then
    echo "No Barista runaways detected."
    return 0
  fi
  pids="$(printf '%s\n' "$candidates" | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^pid=/) {
          sub(/^pid=/, "", $i)
          if ($i != "") print $i
        } else if ($i ~ /^pids=/) {
          sub(/^pids=/, "", $i)
          if ($i != "") print $i
          for (j = i + 1; j <= NF; j++) {
            if ($j ~ /^[0-9]+$/) print $j
          }
        }
      }
    }
  ' | sort -nu)"
  if [ -z "$pids" ]; then
    echo "No cleanup PIDs parsed."
    return 0
  fi
  if [ "$confirm" != "--yes" ]; then
    echo "Dry run: would kill Barista runaway PIDs:"
    printf '%s\n' "$pids"
    echo "Re-run with: process_manager.sh cleanup-runaways --yes"
    return 0
  fi
  printf '%s\n' "$pids" | xargs -n 1 kill
  echo "Killed Barista runaway PIDs:"
  printf '%s\n' "$pids"
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
  load|snapshot)
    load_snapshot
    ;;
  barista)
    barista_processes
    ;;
  runaways)
    runaways
    ;;
  cleanup-runaways)
    cleanup_runaways "${2:-}"
    ;;
  cleanup-mounts|cleanup)
    cleanup_mounts
    ;;
  *)
    print_usage
    exit 1
    ;;
 esac
