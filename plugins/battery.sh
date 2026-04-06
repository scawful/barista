#!/bin/bash

# Battery Widget Script
# Handles battery updates and hover effects

set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

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
    animate_set "$NAME" background.drawing=on background.color="$HIGHLIGHT"
    exit 0
    ;;
  "mouse.exited")
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
  "mouse.exited.global")
    sketchybar --set "$NAME" popup.drawing=off
    animate_set "$NAME" background.drawing=off
    exit 0
    ;;
esac

if [ "$ACTIONS_ARG" != "popup_refresh" ] && [ -n "$BATTERY_FAST_BIN" ] && [ -x "$BATTERY_FAST_BIN" ]; then
  exec "$BATTERY_FAST_BIN" update battery
fi

PMSET_OUTPUT="$(pmset -g batt)"
POWER_SOURCE="$(echo "$PMSET_OUTPUT" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")"
BATTERY_LINE="$(echo "$PMSET_OUTPUT" | tail -1)"
PERCENTAGE="$(echo "$BATTERY_LINE" | grep -Eo "\d+%" | head -1 | cut -d% -f1)"
STATUS_RAW="$(echo "$BATTERY_LINE" | awk -F';' '{print $2}' | xargs)"
TIME_RAW="$(echo "$BATTERY_LINE" | awk -F';' '{print $3}' | xargs)"

if [ -z "$PERCENTAGE" ]; then
  exit 0
fi

STATUS="On Battery"
if [ "$STATUS_RAW" = "charging" ] || [ "$POWER_SOURCE" = "AC Power" ]; then
  STATUS="Charging"
elif [ "$STATUS_RAW" = "charged" ]; then
  STATUS="Charged"
fi

TIME_LABEL=""
TIME_KIND=""
if [ -n "$TIME_RAW" ]; then
  if echo "$TIME_RAW" | grep -qi "finishing charge"; then
    TIME_KIND="Until Full"
  elif echo "$TIME_RAW" | grep -qi "remaining"; then
    TIME_KIND="Remaining"
  fi
  if ! echo "$TIME_RAW" | grep -qi "no estimate"; then
    TIME_LABEL=$(echo "$TIME_RAW" | sed -E 's/present: (true|false)//Ig; s/remaining//Ig; s/finishing charge//Ig; s/^[[:space:]]+//; s/[[:space:]]+$//')
    TIME_LABEL=$(echo "$TIME_LABEL" | xargs 2>/dev/null || true)
  fi
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
CYCLE_COUNT="$(echo "$BATTERY_INFO" | awk -F'= ' '/^[[:space:]]*"CycleCount" =/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"
HEALTH_STATUS="$(echo "$BATTERY_INFO" | awk -F'= ' '/^[[:space:]]*"BatteryHealth" =/ {gsub(/[" ]/,"",$2); print $2; exit}')"
MAX_CAPACITY="$(echo "$BATTERY_INFO" | awk -F'= ' '/^[[:space:]]*"MaxCapacity" =/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"
RAW_MAX_CAPACITY="$(echo "$BATTERY_INFO" | awk -F'= ' '/^[[:space:]]*"AppleRawMaxCapacity" =/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"
DESIGN_CAPACITY="$(echo "$BATTERY_INFO" | awk -F'= ' '/^[[:space:]]*"DesignCapacity" =/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"

HEALTH_PCT=""
HEALTH_BASE=""
if [ -n "$RAW_MAX_CAPACITY" ]; then
  HEALTH_BASE="$RAW_MAX_CAPACITY"
elif [ -n "$MAX_CAPACITY" ] && [ "$MAX_CAPACITY" -gt 100 ] 2>/dev/null; then
  HEALTH_BASE="$MAX_CAPACITY"
fi
if [ -n "$HEALTH_BASE" ] && [ -n "$DESIGN_CAPACITY" ] && [ "$DESIGN_CAPACITY" -gt 0 ] 2>/dev/null; then
  HEALTH_PCT="$(awk -v max="$HEALTH_BASE" -v design="$DESIGN_CAPACITY" 'BEGIN {printf "%.0f", (max / design) * 100}')"
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

sketchybar --set "$NAME" icon="$ICON" label="$LABEL" label.drawing="$LABEL_DRAWING" icon.color="$COLOR" label.color="$COLOR"

sketchybar --set battery.status \
  label="${STATUS}" \
  icon="󰁹" \
  icon.color="$COLOR"

sketchybar --set battery.time \
  label="$TIME_DISPLAY_LABEL" \
  icon="󰥔" \
  icon.color="$BLUE_COLOR"

POWER_LABEL="${POWER_SOURCE:-Unknown}"
case "$POWER_SOURCE" in
  "AC Power") POWER_LABEL="AC" ;;
  "Battery Power") POWER_LABEL="Battery" ;;
esac

sketchybar --set battery.power \
  label="${POWER_LABEL}" \
  icon="" \
  icon.color="$BLUE_COLOR"

sketchybar --set battery.cycle \
  label="${CYCLE_COUNT:-—} cycles" \
  icon="󰑓" \
  icon.color="$BLUE_COLOR"

sketchybar --set battery.health \
  label="$HEALTH_LABEL" \
  icon="󰓽" \
  icon.color="$HEALTH_COLOR"
