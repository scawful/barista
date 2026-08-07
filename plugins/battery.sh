#!/bin/bash

# Battery Widget Script
# Handles battery updates and hover effects

set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."
# shellcheck source=plugins/lib/common.sh
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

if [ -z "${NAME:-}" ]; then
  NAME="battery"
fi

ICON_OVERRIDE="${BARISTA_ICON_BATTERY:-}"
GREEN_COLOR=${1:-"0xffa6e3a1"}
YELLOW_COLOR=${2:-"0xfff9e2af"}
RED_COLOR=${3:-"0xfff38ba8"}
BLUE_COLOR=${4:-"0xff89b4fa"}
ACTIONS_ARG=${5:-}
LABEL_MODE="${BARISTA_BATTERY_LABEL_MODE:-percent}"
BATTERY_FAST_BIN="${BARISTA_BATTERY_FAST_BIN:-}"

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
    sketchybar --set "$NAME" popup.drawing=off
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
esac

if [ "$ACTIONS_ARG" != "popup_refresh" ] && [ -n "$BATTERY_FAST_BIN" ] && [ -x "$BATTERY_FAST_BIN" ]; then
  exec "$BATTERY_FAST_BIN" update battery
fi

trim_whitespace() {
  local value="${1:-}"
  local destination="$2"
  value="${value//$'\t'/ }"
  while [[ "$value" == *"  "* ]]; do
    value="${value//  / }"
  done
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf -v "$destination" '%s' "$value"
}

PMSET_OUTPUT="$(pmset -g batt)"
POWER_SOURCE=""
BATTERY_LINE=""
PERCENTAGE=""
power_re="^Now[[:space:]]+drawing[[:space:]]+from[[:space:]]+'([^']+)'"
percentage_re='([0-9]+)%'
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ $power_re ]]; then
    POWER_SOURCE="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ $percentage_re ]]; then
    BATTERY_LINE="$line"
    PERCENTAGE="${BASH_REMATCH[1]}"
  fi
done <<< "$PMSET_OUTPUT"

if [ -z "$PERCENTAGE" ]; then
  # Match the current set -e pipeline behavior when pmset has no percentage.
  exit 1
fi

STATUS_RAW=""
TIME_RAW=""
IFS=';' read -r _ STATUS_RAW TIME_RAW _ <<< "$BATTERY_LINE"
trim_whitespace "$STATUS_RAW" STATUS_RAW
trim_whitespace "$TIME_RAW" TIME_RAW

STATUS="On Battery"
if [ "$STATUS_RAW" = "charging" ] || [ "$POWER_SOURCE" = "AC Power" ]; then
  STATUS="Charging"
elif [ "$STATUS_RAW" = "charged" ]; then
  STATUS="Charged"
fi

TIME_LABEL=""
TIME_KIND=""
if [ -n "$TIME_RAW" ]; then
  shopt -s nocasematch
  if [[ "$TIME_RAW" =~ finishing[[:space:]]+charge ]]; then
    TIME_KIND="Until Full"
  elif [[ "$TIME_RAW" =~ remaining ]]; then
    TIME_KIND="Remaining"
  fi
  if [[ ! "$TIME_RAW" =~ no[[:space:]]+estimate ]]; then
    read -r -a time_words <<< "$TIME_RAW" || true
    filtered_words=()
    for ((word_index = 0; word_index < ${#time_words[@]}; word_index++)); do
      word="${time_words[$word_index]}"
      if [[ "$word" == remaining ]]; then
        continue
      fi
      if [[ "$word" == finishing ]] \
          && [ $((word_index + 1)) -lt ${#time_words[@]} ] \
          && [[ "${time_words[$((word_index + 1))]}" == charge ]]; then
        word_index=$((word_index + 1))
        continue
      fi
      if [[ "$word" == present: ]]; then
        if [ $((word_index + 1)) -lt ${#time_words[@]} ] \
            && { [[ "${time_words[$((word_index + 1))]}" == true ]] \
              || [[ "${time_words[$((word_index + 1))]}" == false ]]; }; then
          word_index=$((word_index + 1))
        fi
        continue
      fi
      if [[ "$word" == present:true ]] || [[ "$word" == present:false ]]; then
        continue
      fi
      filtered_words+=("$word")
    done
    TIME_LABEL="${filtered_words[*]:-}"
    trim_whitespace "$TIME_LABEL" TIME_LABEL
  fi
  shopt -u nocasematch
fi
if [ "$STATUS" = "Charging" ] && [ -n "$TIME_LABEL" ] && [ "$TIME_KIND" = "Remaining" ]; then
  TIME_KIND="Until Full"
fi

case "${PERCENTAGE}" in
  9[0-9]|100) ICON=""
  ;;
  [6-8][0-9]) ICON=""
  ;;
  [3-5][0-9]) ICON=""
  ;;
  [1-2][0-9]) ICON=""
  ;;
  *) ICON=""
esac

COLOR="$GREEN_COLOR"

if [ "$PERCENTAGE" -lt 50 ]; then
  COLOR="$YELLOW_COLOR"
fi

if [ "$PERCENTAGE" -lt 20 ]; then
  COLOR="$RED_COLOR"
fi

if [ "$STATUS" = "Charging" ]; then
  ICON=""
  COLOR="$BLUE_COLOR"
fi

if [ -n "$ICON_OVERRIDE" ]; then
  ICON="$ICON_OVERRIDE"
fi

LABEL="${PERCENTAGE}%"
LABEL_DRAWING="on"
case "$LABEL_MODE" in
  icon|off|none)
    LABEL=""
    LABEL_DRAWING="off"
    ;;
esac

BATTERY_INFO="$(ioreg -rc AppleSmartBattery 2>/dev/null || true)"
CYCLE_COUNT=""
HEALTH_STATUS=""
MAX_CAPACITY=""
RAW_MAX_CAPACITY=""
DESIGN_CAPACITY=""
cycle_re='^[[:space:]]*"CycleCount"[[:space:]]*=[[:space:]]*([0-9]+)'
health_re='^[[:space:]]*"BatteryHealth"[[:space:]]*=[[:space:]]*"([^"]*)"'
max_re='^[[:space:]]*"MaxCapacity"[[:space:]]*=[[:space:]]*([0-9]+)'
raw_max_re='^[[:space:]]*"AppleRawMaxCapacity"[[:space:]]*=[[:space:]]*([0-9]+)'
design_re='^[[:space:]]*"DesignCapacity"[[:space:]]*=[[:space:]]*([0-9]+)'
while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$CYCLE_COUNT" ] && [[ "$line" =~ $cycle_re ]]; then
    CYCLE_COUNT="${BASH_REMATCH[1]}"
  elif [ -z "$HEALTH_STATUS" ] && [[ "$line" =~ $health_re ]]; then
    HEALTH_STATUS="${BASH_REMATCH[1]// /}"
  elif [ -z "$RAW_MAX_CAPACITY" ] && [[ "$line" =~ $raw_max_re ]]; then
    RAW_MAX_CAPACITY="${BASH_REMATCH[1]}"
  elif [ -z "$MAX_CAPACITY" ] && [[ "$line" =~ $max_re ]]; then
    MAX_CAPACITY="${BASH_REMATCH[1]}"
  elif [ -z "$DESIGN_CAPACITY" ] && [[ "$line" =~ $design_re ]]; then
    DESIGN_CAPACITY="${BASH_REMATCH[1]}"
  fi
done <<< "$BATTERY_INFO"

HEALTH_PCT=""
HEALTH_BASE=""
if [ -n "$RAW_MAX_CAPACITY" ]; then
  HEALTH_BASE="$RAW_MAX_CAPACITY"
elif [ -n "$MAX_CAPACITY" ] && [ "$MAX_CAPACITY" -gt 100 ] 2>/dev/null; then
  HEALTH_BASE="$MAX_CAPACITY"
fi
if [ -n "$HEALTH_BASE" ] && [ -n "$DESIGN_CAPACITY" ] && [ "$DESIGN_CAPACITY" -gt 0 ] 2>/dev/null; then
  # Preserve macOS awk's round-to-even %.0f behavior without another process.
  health_numerator=$((HEALTH_BASE * 100))
  HEALTH_PCT=$((health_numerator / DESIGN_CAPACITY))
  health_remainder=$((health_numerator % DESIGN_CAPACITY))
  if [ $((health_remainder * 2)) -gt "$DESIGN_CAPACITY" ] \
      || { [ $((health_remainder * 2)) -eq "$DESIGN_CAPACITY" ] \
        && [ $((HEALTH_PCT % 2)) -ne 0 ]; }; then
    HEALTH_PCT=$((HEALTH_PCT + 1))
  fi
fi

if [ -n "$HEALTH_PCT" ]; then
  HEALTH_LABEL="${HEALTH_PCT}%"
elif [ -n "$HEALTH_STATUS" ]; then
  HEALTH_LABEL="${HEALTH_STATUS}"
else
  HEALTH_LABEL="—"
fi

TIME_DISPLAY_LABEL="—"
if [ -n "$TIME_LABEL" ]; then
  if [ "$TIME_KIND" = "Until Full" ]; then
    TIME_DISPLAY_LABEL="$TIME_LABEL to full"
  elif [ "$TIME_KIND" = "Remaining" ]; then
    TIME_DISPLAY_LABEL="$TIME_LABEL left"
  else
    TIME_DISPLAY_LABEL="$TIME_LABEL"
  fi
elif [ "$STATUS" = "Charged" ]; then
  TIME_DISPLAY_LABEL="Fully charged"
elif [ "$STATUS" = "Charging" ]; then
  TIME_DISPLAY_LABEL="Charging"
fi

HEALTH_COLOR="$GREEN_COLOR"
if [ -n "$HEALTH_PCT" ] && [ "$HEALTH_PCT" -lt 80 ] 2>/dev/null; then
  HEALTH_COLOR="$YELLOW_COLOR"
fi
if [ -n "$HEALTH_PCT" ] && [ "$HEALTH_PCT" -lt 60 ] 2>/dev/null; then
  HEALTH_COLOR="$RED_COLOR"
fi

POWER_LABEL="${POWER_SOURCE:-Unknown}"
case "$POWER_SOURCE" in
  "AC Power") POWER_LABEL="AC" ;;
  "Battery Power") POWER_LABEL="Battery" ;;
esac

sketchybar \
  --set "$NAME" icon="$ICON" label="$LABEL" label.drawing="$LABEL_DRAWING" icon.color="$COLOR" label.color="$COLOR" \
  --set battery.status label="${STATUS}" icon="󰁹" icon.color="$COLOR" \
  --set battery.time label="$TIME_DISPLAY_LABEL" icon="󰥔" icon.color="$BLUE_COLOR" \
  --set battery.power label="${POWER_LABEL}" icon="" icon.color="$BLUE_COLOR" \
  --set battery.cycle label="${CYCLE_COUNT:-—} cycles" icon="󰑓" icon.color="$BLUE_COLOR" \
  --set battery.health label="$HEALTH_LABEL" icon="󰓽" icon.color="$HEALTH_COLOR"
