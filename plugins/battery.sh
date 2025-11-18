#!/bin/sh

GREEN_COLOR=${1:-"0xffa6e3a1"}
YELLOW_COLOR=${2:-"0xfff9e2af"}
RED_COLOR=${3:-"0xfff38ba8"}
BLUE_COLOR=${4:-"0xff89b4fa"}

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
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

if [[ "$CHARGING" != "" ]]; then
  ICON=""
  COLOR="$BLUE_COLOR"
fi

if [ -z "$NAME" ]; then
  NAME="battery"
fi

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color="$COLOR" label.color="$COLOR"
