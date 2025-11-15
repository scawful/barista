#!/bin/sh

# Some events send additional information specific to the event in the $INFO
# variable. E.g. the front_app_switched event sends the name of the newly
# focused application in the $INFO variable:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

if [ "$SENDER" = "front_app_switched" ]; then
  # Based on the name of the application, use all-the-icons
  # to find a suitable icon for the application:
  if [ "$INFO" = "Terminal" ] || [ "$INFO" = "iTerm2" ]; then
    ICON=" " # 󰆍 
  elif [ "$INFO" = "Firefox" ]; then
    ICON=" "
  elif [ "$INFO" = "Messages" ]; then
    ICON=""
  elif [ "$INFO" = "Code" ]; then
    ICON=" "
  elif [ "$INFO" = "Emacs" ]; then
    ICON="" # ""
  elif [ "$INFO" = "Finder" ]; then
    ICON="󰀶 "
  elif [ "$INFO" = "Spotify" ]; then
    ICON=" "
  elif [ "$INFO" = "Discord" ]; then
    ICON=" "
  elif [ "$INFO" = "Mail" ]; then
    ICON=" "
  elif [ "$INFO" = "Mesen" ]; then
    ICON="󰺷 "
  elif [ "$INFO" = "Maps" ]; then
    ICON=""
  elif [ "$INFO" = "Calendar" ]; then
    ICON=" "
  elif [ "$INFO" = "Notes" ]; then
    ICON=" "
  elif [ "$INFO" = "Reminders" ]; then
    ICON=" "
  elif [ "$INFO" = "Music" ]; then
    ICON=" "
  elif [ "$INFO" = "Photos" ]; then
    ICON=" "
  elif [ "$INFO" = "ChatGPT" ]; then
    ICON="󰙴 "
  elif [ "$INFO" = "Parallels Desktop" ]; then
    ICON=" "
  elif [ "$INFO" = "Gimp" ]; then
    ICON=" "
  else
    ICON="󰣆 "
  fi
  sketchybar --set "$NAME" label="$INFO"
  SPACE=$(yabai -m query --spaces | jq -r ".[] | select(.[\"has-focus\"] == true) | .index")
  if [ -n "$SPACE" ]; then
    sketchybar --set "space.$SPACE" icon="$ICON"
  fi
fi
