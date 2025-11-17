#!/bin/sh

INTERFACE=${SKETCHYBAR_NET_INTERFACE:-en0}
INFO="$(ifconfig "$INTERFACE" 2>/dev/null || true)"

if [ -z "$INFO" ]; then
  sketchybar --set "$NAME" icon="󰖪" icon.color="0xfff38ba8" label="No iface"
  exit 0
fi

STATE=$(printf '%s\n' "$INFO" | awk -F': ' '/status:/{print $2; exit}')
IP=$(printf '%s\n' "$INFO" | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')

get_wifi_name() {
  local ssid=""
  local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
  if [ -x "$airport" ]; then
    ssid=$("$airport" -I 2>/dev/null | awk -F': ' '/ SSID/{print $2; exit}')
  fi
  if [ -z "$ssid" ] && command -v networksetup >/dev/null 2>&1; then
    ssid=$(networksetup -getairportnetwork "$INTERFACE" 2>/dev/null | awk -F': ' '/Current Wi-Fi Network:/{print $2; exit}')
  fi
  printf '%s' "$ssid"
}

SSID=""
if [ "${INTERFACE#en}" != "$INTERFACE" ] || [ "${INTERFACE#ath}" != "$INTERFACE" ]; then
  SSID=$(get_wifi_name)
fi

if [ -z "$STATE" ]; then
  STATE="down"
fi

ICON="󰖩"
COLOR="0xffa6e3a1"
LABEL="offline"

if [ "$STATE" = "active" ]; then
  # Show only SSID for wifi or "Connected" for ethernet
  # No IP address display per user request
  if [ -n "$SSID" ]; then
    LABEL="$SSID"
  else
    LABEL="Connected"
  fi
else
  COLOR="0xfff38ba8"
  ICON="󰖪"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
