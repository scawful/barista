#!/bin/bash
# halext-org Integration Menu
# Provides task management, calendar events, and LLM suggestions

set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
CODE_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
STATE_FILE="${CONFIG_DIR}/state.json"
CACHE_DIR="${CONFIG_DIR}/cache"
TASKS_CACHE="${CACHE_DIR}/halext_tasks.json"
CALENDAR_CACHE="${CACHE_DIR}/halext_calendar.json"
FRONTEND_CTL="${CODE_DIR}/halext-org/scripts/frontend-service.sh"

# Read configuration from state.json
read_config() {
  if [ ! -f "$STATE_FILE" ]; then
    echo ""
    return
  fi

  local key="$1"
  local default="${2:-}"

  value=$(lua -e "
    local json = require('json')
    local file = io.open('${STATE_FILE}', 'r')
    if file then
      local content = file:read('*a')
      file:close()
      local ok, data = pcall(json.decode, content)
      if ok and type(data) == 'table' then
        local keys = {}
        for k in string.gmatch('${key}', '[^.]+') do
          table.insert(keys, k)
        end
        local current = data
        for _, k in ipairs(keys) do
          if type(current) ~= 'table' then
            print('${default}')
            os.exit(0)
          end
          current = current[k]
          if current == nil then
            print('${default}')
            os.exit(0)
          end
        end
        if type(current) == 'boolean' then
          print(current and 'true' or 'false')
        else
          print(tostring(current))
        end
      else
        print('${default}')
      end
    else
      print('${default}')
    end
  " 2>/dev/null)

  echo "${value:-$default}"
}

# Check if halext-org integration is enabled
ENABLED=$(read_config "integrations.halext.enabled" "false")
if [ "$ENABLED" != "true" ]; then
  sketchybar -m --set "$NAME" popup.drawing=off
  osascript -e 'display notification "halext-org integration is not enabled. Please configure it in the control panel." with title "SketchyBar"' >/dev/null 2>&1 || true
  exit 0
fi

# Menu configuration
SERVER_URL=$(read_config "integrations.halext.server_url" "")
SHOW_TASKS=$(read_config "integrations.halext.show_tasks" "true")
SHOW_CALENDAR=$(read_config "integrations.halext.show_calendar" "true")
SHOW_SUGGESTIONS=$(read_config "integrations.halext.show_suggestions" "true")

# Check for valid configuration
if [ -z "$SERVER_URL" ]; then
  sketchybar -m --set "$NAME" popup.drawing=off
  osascript -e 'display notification "halext-org server URL not configured." with title "SketchyBar"' >/dev/null 2>&1 || true
  exit 0
fi

# Handle menu actions
case "${1:-toggle}" in
  toggle)
    sketchybar -m --set "$NAME" popup.drawing=toggle
    ;;
  refresh)
    # Clear cache and force refresh
    rm -f "$TASKS_CACHE" "$CALENDAR_CACHE"
    # Trigger a refresh by calling the halext module
    sketchybar -m --set "$NAME" label="Refreshing..."
    sleep 0.5
    sketchybar -m --set "$NAME" label="halext"
    ;;
  configure)
    # Open control panel to Integrations tab
    "${CONFIG_DIR}/gui/bin/config_menu_v2" &
    ;;
  open_tasks)
    open "${SERVER_URL}/tasks"
    ;;
  open_calendar)
    open "${SERVER_URL}/calendar"
    ;;
  open_suggestions)
    open "${SERVER_URL}/llm/suggestions"
    ;;
  frontend_start)
    if [ -x "$FRONTEND_CTL" ]; then
      "$FRONTEND_CTL" start >/dev/null 2>&1 && osascript -e 'display notification "halext frontend started" with title "SketchyBar"' >/dev/null 2>&1 || true
    else
      osascript -e 'display notification "frontend-service.sh not found" with title "SketchyBar"' >/dev/null 2>&1 || true
    fi
    ;;
  frontend_stop)
    if [ -x "$FRONTEND_CTL" ]; then
      "$FRONTEND_CTL" stop >/dev/null 2>&1 && osascript -e 'display notification "halext frontend stopped" with title "SketchyBar"' >/dev/null 2>&1 || true
    else
      osascript -e 'display notification "frontend-service.sh not found" with title "SketchyBar"' >/dev/null 2>&1 || true
    fi
    ;;
  frontend_restart)
    if [ -x "$FRONTEND_CTL" ]; then
      "$FRONTEND_CTL" restart >/dev/null 2>&1 && osascript -e 'display notification "halext frontend restarted" with title "SketchyBar"' >/dev/null 2>&1 || true
    else
      osascript -e 'display notification "frontend-service.sh not found" with title "SketchyBar"' >/dev/null 2>&1 || true
    fi
    ;;
  frontend_status)
    if [ -x "$FRONTEND_CTL" ]; then
      status=$("$FRONTEND_CTL" status 2>/dev/null | head -n 1)
      osascript -e "display notification \"${status}\" with title \"halext frontend\"" >/dev/null 2>&1 || true
    else
      osascript -e 'display notification "frontend-service.sh not found" with title "SketchyBar"' >/dev/null 2>&1 || true
    fi
    ;;
  *)
    # Default: toggle menu
    sketchybar -m --set "$NAME" popup.drawing=toggle
    ;;
esac
