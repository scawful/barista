#!/bin/zsh
# cortex_widget.sh - SketchyBar widget update script for Cortex
# Configurable, low-overhead status + HAFS metrics display.

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

ICON_ON="${CORTEX_ICON_ON:-󰪴}"
ICON_OFF="${CORTEX_ICON_OFF:-󰪵}"
COLOR_ON="${CORTEX_COLOR_ON:-0xffa6e3a1}"
COLOR_OFF="${CORTEX_COLOR_OFF:-0xff6c7086}"
LABEL_COLOR="${CORTEX_LABEL_COLOR:-0xffcdd6f4}"
LABEL_FONT="${CORTEX_LABEL_FONT:-}"
LABEL_MODE="${CORTEX_LABEL_MODE:-training}" # training|hafs|status|none
LABEL_PREFIX="${CORTEX_LABEL_PREFIX:-HAFS}"
LABEL_ON="${CORTEX_LABEL_ON:-Cortex}"
LABEL_OFF="${CORTEX_LABEL_OFF:-Off}"
LABEL_TEMPLATE="${CORTEX_LABEL_TEMPLATE:-}"
SHOW_LABEL="${CORTEX_SHOW_LABEL:-1}"
CACHE_TTL="${CORTEX_CACHE_TTL:-60}"
CACHE_FILE="${CORTEX_CACHE_FILE:-$HOME/.cache/cortex/sketchybar_hafs.cache}"
CORTEX_CONFIG="${CORTEX_CONFIG_PATH:-$HOME/.config/cortex/config.json}"

needs_agents=0
needs_training=0
if [[ "$LABEL_MODE" == "hafs" ]]; then
  needs_agents=1
elif [[ "$LABEL_MODE" == "training" ]]; then
  needs_training=1
fi
if [[ -n "$LABEL_TEMPLATE" ]]; then
  if [[ "$LABEL_TEMPLATE" == *"%agents%"* || "$LABEL_TEMPLATE" == *"%entries%"* ]]; then
    needs_agents=1
  fi
  if [[ "$LABEL_TEMPLATE" == *"%datasets%"* || "$LABEL_TEMPLATE" == *"%samples%"* ]]; then
    needs_training=1
  fi
fi

is_running() {
  pgrep -x cortex >/dev/null 2>&1
}

resolve_context_root() {
  local root="${HAFS_CONTEXT_ROOT:-}"
  if [[ -z "$root" && -f "$CORTEX_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    root="$(jq -r '.integrations.hafs.contextRoot // empty' "$CORTEX_CONFIG" 2>/dev/null || true)"
  fi
  if [[ -z "$root" ]]; then
    root="$HOME/.context"
  fi
  root="${root/#\~/$HOME}"
  printf '%s' "$root"
}

format_count() {
  local n="${1:-0}"
  if [[ "$n" -ge 1000000 ]]; then
    awk -v n="$n" 'BEGIN { printf "%.1fm", n/1000000 }'
  elif [[ "$n" -ge 1000 ]]; then
    awk -v n="$n" 'BEGIN { printf "%.1fk", n/1000 }'
  else
    printf '%s' "$n"
  fi
}

read_metrics() {
  if [[ "$needs_agents" -eq 0 && "$needs_training" -eq 0 ]]; then
    printf '0 0 0 0'
    return
  fi

  local now
  now="$(date +%s)"

  if [[ -f "$CACHE_FILE" && "$CACHE_TTL" -gt 0 ]]; then
    local mtime
    mtime="$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
    if [[ $((now - mtime)) -lt "$CACHE_TTL" ]]; then
      read -r agent_count memory_count dataset_count sample_count < "$CACHE_FILE" || true
      printf '%s %s %s %s' "${agent_count:-0}" "${memory_count:-0}" "${dataset_count:-0}" "${sample_count:-0}"
      return
    fi
  fi

  local root agent_dir agent_count memory_count
  local training_dir datasets_dir dataset_count sample_count
  root="$(resolve_context_root)"
  agent_count=0
  memory_count=0
  if [[ "$needs_agents" -eq 1 ]]; then
    agent_dir="$root/history/agents"
    if [[ -d "$agent_dir" ]]; then
      agent_count="$(find "$agent_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
      memory_count="$(find "$agent_dir" -mindepth 3 -maxdepth 3 -type f -name '*.json' -path '*/entries/*' 2>/dev/null | wc -l | tr -d ' ')"
    fi
  fi

  training_dir="$root/training"
  datasets_dir="$training_dir/datasets"
  dataset_count=0
  sample_count=0
  if [[ "$needs_training" -eq 1 && -d "$datasets_dir" ]]; then
    dataset_count="$(find "$datasets_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    if command -v jq >/dev/null 2>&1; then
      while IFS= read -r stats_path; do
        value="$(jq -r '.final_count // .total_generated // 0' "$stats_path" 2>/dev/null || echo 0)"
        case "$value" in
          ''|*[!0-9]*) value=0 ;;
        esac
        sample_count=$((sample_count + value))
      done < <(find "$datasets_dir" -mindepth 2 -maxdepth 2 -type f -name 'stats.json' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
      sample_count="$(python3 - "$datasets_dir" <<'PY'
import json
import os
import sys

root = sys.argv[1]
total = 0
for name in os.listdir(root):
    path = os.path.join(root, name, "stats.json")
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        continue
    value = data.get("final_count")
    generated = data.get("total_generated", 0)
    if value is None or (isinstance(value, (int, float)) and value <= 0):
        value = generated
    try:
        total += int(value)
    except Exception:
        pass
print(total)
PY
)"
    fi
  fi

  cache_dir="${CACHE_FILE%/*}"
  mkdir -p "$cache_dir"
  printf '%s %s %s %s\n' "$agent_count" "$memory_count" "$dataset_count" "$sample_count" > "$CACHE_FILE" 2>/dev/null || true
  printf '%s %s %s %s' "$agent_count" "$memory_count" "$dataset_count" "$sample_count"
}

if is_running; then
  STATUS="running"
  ICON="$ICON_ON"
  COLOR="$COLOR_ON"
else
  STATUS="stopped"
  ICON="$ICON_OFF"
  COLOR="$COLOR_OFF"
fi

LABEL=""
LABEL_DRAWING="on"
if [[ "$SHOW_LABEL" == "0" || "$LABEL_MODE" == "none" ]]; then
  LABEL_DRAWING="off"
elif [[ "$LABEL_MODE" == "status" ]]; then
  if [[ "$STATUS" == "running" ]]; then
    LABEL="$LABEL_ON"
  else
    LABEL="$LABEL_OFF"
  fi
else
  read -r agent_count memory_count dataset_count sample_count <<<"$(read_metrics)"
  agent_count="${agent_count:-0}"
  memory_count="${memory_count:-0}"
  dataset_count="${dataset_count:-0}"
  sample_count="${sample_count:-0}"
  if [[ -n "$LABEL_TEMPLATE" ]]; then
    LABEL="${LABEL_TEMPLATE//%prefix%/$LABEL_PREFIX}"
    LABEL="${LABEL//%status%/$STATUS}"
    LABEL="${LABEL//%agents%/$agent_count}"
    LABEL="${LABEL//%entries%/$(format_count "$memory_count")}"
    LABEL="${LABEL//%datasets%/$dataset_count}"
    LABEL="${LABEL//%samples%/$(format_count "$sample_count")}"
  elif [[ "$LABEL_MODE" == "training" ]]; then
    LABEL="${LABEL_PREFIX} ${dataset_count} • $(format_count "$sample_count")"
  else
    LABEL="${LABEL_PREFIX} ${agent_count} • $(format_count "$memory_count")"
  fi
fi

args=(--set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL" label.color="$LABEL_COLOR" label.drawing="$LABEL_DRAWING")
if [[ -n "$LABEL_FONT" ]]; then
  args+=(label.font="$LABEL_FONT")
fi

sketchybar "${args[@]}"
