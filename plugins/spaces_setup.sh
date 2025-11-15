#!/bin/bash

# Dynamic space setup for macOS Tahoe
# This script creates sketchybar spaces based on actual yabai spaces

# Get the actual space indices from yabai
SPACES=$(yabai -m query --spaces | jq -r '.[].index' | sort -n)

# Clear existing spaces
sketchybar --remove '/space\..*/'

# Create spaces dynamically
space_icons=("󰀵" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
icon_index=0

for space_index in $SPACES; do
    if [ $icon_index -lt ${#space_icons[@]} ]; then
        icon="${space_icons[$icon_index]}"
    else
        icon="$space_index"
    fi
    
    sketchybar --add space "space.$space_index" left \
               --set "space.$space_index" space="$space_index" \
                                        icon="$icon" \
                                        icon.padding_left=5 \
                                        icon.padding_right=5 \
                                        label.drawing=off \
                                        background.color="0x20ffffff" \
                                        background.corner_radius=7 \
                                        background.height=18 \
                                        script="$CONFIG_DIR/plugins/space.sh" \
                                        click_script="yabai -m space --focus $space_index"
    
    ((icon_index++))
done

# Add bracket for all spaces
sketchybar --add bracket spaces '/space\..*/' \
           --set spaces background.color="0x40000000" \
                        background.corner_radius=7 \
                        background.height=20
