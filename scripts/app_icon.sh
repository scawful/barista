#!/bin/bash
# app_icon.sh - Map application names to Nerd Font icons
# Used by space.sh and front_app.sh for app icon display

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

APP_NAME="$1"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
ICON_MAP="${ICON_MAP:-$CONFIG_DIR/icon_map.json}"

if [ -n "$APP_NAME" ] && [ -f "$ICON_MAP" ] && command -v jq >/dev/null 2>&1; then
  custom_icon=$(jq -r --arg app "$APP_NAME" '.[$app] // empty' "$ICON_MAP" 2>/dev/null || true)
  if [ -n "$custom_icon" ] && [ "$custom_icon" != "null" ]; then
    printf '%s' "$custom_icon"
    exit 0
  fi
fi

# Case-insensitive matching with Nerd Font glyphs
case "$APP_NAME" in
  # Terminals
  "Terminal"|"终端") echo "" ;;
  "iTerm"|"iTerm2") echo "" ;;
  "Alacritty") echo "󰄛" ;;
  "kitty") echo "󰄛" ;;
  "Warp") echo "󱓞" ;;
  "WezTerm") echo "" ;;
  "Hyper") echo "󰆍" ;;
  "Ghostty"|"ghostty") echo "" ;;
  
  # Editors & IDEs
  "Code"|"Visual Studio Code"|"VSCode") echo "󰨞" ;;
  "Cursor"|"cursor") echo "󰨞" ;;
  "Claude"|"claude") echo "󰭻" ;;
  "Claude Code"|"claude code") echo "󰭻" ;;
  "Xcode") echo "" ;;
  "Emacs") echo "" ;;
  "Vim"|"MacVim") echo "" ;;
  "Neovim"|"nvim"|"Neovide") echo "" ;;
  "Sublime Text") echo "" ;;
  "Atom") echo "" ;;
  "IntelliJ IDEA"|"IntelliJ") echo "" ;;
  "PyCharm") echo "" ;;
  "WebStorm") echo "󰜈" ;;
  "GoLand") echo "" ;;
  "Rider") echo "󱘗" ;;
  "Android Studio") echo "" ;;
  "Zed") echo "󰛡" ;;
  
  # Browsers
  "Safari"|"Safari Technology Preview") echo "󰀹" ;;
  "Google Chrome"|"Chrome"|"Chromium") echo "" ;;
  "Firefox"|"Firefox Developer Edition"|"firefox") echo "" ;;
  "Arc") echo "󰞍" ;;
  "Brave Browser") echo "󰊯" ;;
  "Microsoft Edge") echo "󰇩" ;;
  "Vivaldi") echo "󰖟" ;;
  "Orion"|"Orion RC") echo "󰖟" ;;
  
  # Communication
  "Discord"|"Discord Canary"|"Discord PTB") echo "󰙯" ;;
  "Slack") echo "󰒱" ;;
  "Microsoft Teams"|"Teams") echo "󰊻" ;;
  "Messages"|"messages"|"信息") echo "󰍦" ;;
  "Telegram") echo "󰍦" ;;
  "WhatsApp"|"‎WhatsApp") echo "󰖣" ;;
  "Signal") echo "󰭹" ;;
  "Messenger") echo "󰈎" ;;
  "Zoom"|"zoom.us") echo "󰕧" ;;
  "FaceTime") echo "󰕧" ;;
  "Skype") echo "󰒯" ;;
  
  # Productivity
  "Finder"|"访达") echo "󰀶" ;;
  "Notes"|"备忘录") echo "󰎚" ;;
  "Reminders"|"提醒事项") echo "󰃮" ;;
  "Calendar"|"日历"|"Fantastical") echo "" ;;
  "Mail"|"邮件") echo "󰇮" ;;
  "Preview"|"预览") echo "󰈙" ;;
  "System Settings"|"System Preferences"|"系统设置") echo "" ;;
  "App Store") echo "󰓇" ;;
  
  # Creative
  "Figma") echo "" ;;
  "Sketch") echo "󰁿" ;;
  "Photoshop"|"Adobe Photoshop") echo "" ;;
  "Affinity Photo"|"Affinity Photo 2") echo "" ;;
  "Affinity Designer"|"Affinity Designer 2") echo "󰃣" ;;
  "Blender") echo "󰂫" ;;
  "Final Cut Pro") echo "󰕼" ;;
  
  # Media
  "Music"|"音乐"|"Apple Music") echo "󰎈" ;;
  "Spotify"|"spotify") echo "" ;;
  "VLC") echo "󰕼" ;;
  "Podcasts"|"播客") echo "󰎈" ;;
  "TIDAL") echo "󰓃" ;;
  
  # Development Tools
  "Docker"|"Docker Desktop") echo "" ;;
  "GitHub Desktop") echo "" ;;
  "Tower") echo "" ;;
  "Insomnia") echo "󰘯" ;;
  "Postman") echo "󰘯" ;;
  
  # Notes & Writing
  "Obsidian") echo "󰎚" ;;
  "Notion") echo "󰈙" ;;
  "Bear") echo "󰏪" ;;
  "Logseq") echo "󱓧" ;;
  "Typora") echo "󰈙" ;;
  
  # Password & Security
  "1Password") echo "󰢁" ;;
  "Bitwarden") echo "󰞀" ;;
  "KeePassXC") echo "󰌆" ;;
  
  # Utilities
  "Alfred") echo "󰌑" ;;
  "Spotlight") echo "󰍉" ;;
  "Activity Monitor") echo "󰨇" ;;
  "Raycast") echo "󰑓" ;;
  "Antigravity"|"antigravity") echo "" ;;
  "LM Studio"|"lm studio") echo "󰭻" ;;

  # Zelda / Oracle tooling
  "Oracle Agent Manager"|"oracle_manager_gui"|"oracle_hub"|"Oracle") echo "󰯙" ;;
  
  # Games
  "Steam") echo "" ;;
  
  # Default fallback
  *) echo "󰣆" ;;
esac
