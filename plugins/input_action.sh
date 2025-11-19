#!/bin/bash

# Input Action Handler
# Handles actions from the input widget popup

ACTION="$1"

case "$ACTION" in
  "command")
    CMD=$(osascript -e 'text returned of (display dialog "Enter shell command:" default answer "" buttons {"Cancel", "Run"} default button "Run")')
    if [ -n "$CMD" ]; then
      # Run in background and notify
      eval "$CMD" &
      osascript -e "display notification \"Command executed: $CMD\" with title \"SketchyBar\""
    fi
    ;;
  "ai")
    PROMPT=$(osascript -e 'text returned of (display dialog "Ask AI:" default answer "" buttons {"Cancel", "Ask"} default button "Ask")')
    if [ -n "$PROMPT" ]; then
      # Assuming ollama_prompt.sh exists and handles the prompt
      # We might need to pass it differently depending on how ollama_prompt.sh works
      # For now, let's assume it takes an argument or we just run it
      # If ollama_prompt.sh is interactive, we might need a terminal
      
      # Let's try to use the existing ollama_prompt.sh if possible, or just open a terminal with it
      open -a Terminal "$HOME/.config/sketchybar/plugins/ollama_prompt.sh" --args "$PROMPT"
    fi
    ;;
esac

sketchybar --set input popup.drawing=off

