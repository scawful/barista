-- Cortex Integration Module for Barista
-- The brain layer that orchestrates AFS, Barista, and halext-org
--
-- Install: Copy to ~/.config/sketchybar/modules/integrations/cortex.lua
-- Or symlink: ln -sf ~/src/cortex/barista/cortex.lua ~/.config/sketchybar/modules/integrations/

local cortex = {}

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local CORTEX_CLI = CODE_DIR .. "/cortex/bin/cortex-cli"
local CORTEX_BIN = HOME .. "/.local/bin/cortex"

-- Configuration
cortex.config = {
  cli_path = CORTEX_CLI,
  bin_path = CORTEX_BIN,
  repo_path = CODE_DIR .. "/cortex",
}

-- Notification names (match CortexNotifications.swift)
cortex.notifications = {
  toggle = "com.scawful.cortex.dashboard.toggle",
  refresh = "com.scawful.cortex.refresh",
  quit = "com.scawful.cortex.quit",
  restart = "com.scawful.cortex.restart",
}

-- Post distributed notification via Swift
local function post_notification(name)
  local swift_cmd = string.format([[
swift - <<'EOF' 2>/dev/null
import Foundation
let center = DistributedNotificationCenter.default()
center.postNotificationName(
    Notification.Name("%s"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
Thread.sleep(forTimeInterval: 0.05)
EOF
]], name)
  os.execute(swift_cmd)
end

-- Check if Cortex is running
function cortex.is_running()
  local handle = io.popen("pgrep -x cortex >/dev/null 2>&1 && echo 1 || echo 0")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Get Cortex status for widgets
function cortex.get_status()
  if cortex.is_running() then
    return "running", "󰪴", "#a6e3a1"  -- icon, green
  else
    return "stopped", "󰪵", "#6c7086"  -- icon, gray
  end
end

-- Start Cortex
function cortex.start()
  if cortex.is_running() then
    return true, "Already running"
  end

  local bin = cortex.config.bin_path
  if io.open(bin, "r") then
    os.execute(string.format("%s &", bin))
    return true, "Started"
  end
  return false, "Binary not found"
end

-- Stop Cortex
function cortex.stop()
  if not cortex.is_running() then
    return true, "Not running"
  end
  post_notification(cortex.notifications.quit)
  return true, "Stopping"
end

-- Restart Cortex
function cortex.restart()
  post_notification(cortex.notifications.restart)
  return true, "Restarting"
end

-- Toggle dashboard
function cortex.toggle()
  if not cortex.is_running() then
    cortex.start()
    os.execute("sleep 0.3")
  end
  post_notification(cortex.notifications.toggle)
  return true
end

-- Refresh widgets
function cortex.refresh()
  if not cortex.is_running() then
    return false, "Not running"
  end
  post_notification(cortex.notifications.refresh)
  return true
end

-- Create menu items for barista
function cortex.create_menu_items(ctx)
  local items = {}
  local running = cortex.is_running()
  local status_icon = running and "󰪴" or "󰪵"
  local status_color = running and "#a6e3a1" or "#6c7086"

  -- Header
  table.insert(items, {
    type = "header",
    name = "cortex.header",
    label = "Cortex",
    icon = status_icon,
    icon_color = status_color,
  })

  -- Toggle Dashboard
  table.insert(items, {
    type = "item",
    name = "cortex.toggle",
    icon = "󰕮",
    label = "Toggle Dashboard",
    action = function()
      cortex.toggle()
    end,
    -- Alternative CLI action for non-lua contexts
    shell_action = CORTEX_CLI .. " toggle",
  })

  -- Refresh
  if running then
    table.insert(items, {
      type = "item",
      name = "cortex.refresh",
      icon = "󰑐",
      label = "Refresh Widgets",
      action = function()
        cortex.refresh()
      end,
      shell_action = CORTEX_CLI .. " refresh",
    })
  end

  table.insert(items, { type = "separator", name = "cortex.sep1" })

  -- Start/Stop/Restart
  if running then
    table.insert(items, {
      type = "item",
      name = "cortex.restart",
      icon = "󰜉",
      label = "Restart Cortex",
      action = function()
        cortex.restart()
      end,
      shell_action = CORTEX_CLI .. " restart",
    })

    table.insert(items, {
      type = "item",
      name = "cortex.stop",
      icon = "󰓛",
      label = "Stop Cortex",
      action = function()
        cortex.stop()
      end,
      shell_action = CORTEX_CLI .. " stop",
    })
  else
    table.insert(items, {
      type = "item",
      name = "cortex.start",
      icon = "󰐊",
      label = "Start Cortex",
      action = function()
        cortex.start()
      end,
      shell_action = CORTEX_CLI .. " start",
    })
  end

  -- Admin Section (halext-org)
  table.insert(items, {
    type = "item",
    name = "cortex.halext",
    icon = "󰒋",
    label = "halext-org Dashboard",
    action = ctx.open_url("https://org.halext.org"),
  })

  return items
end

-- Create a sketchybar widget item
local function build_env_script(env, script_path)
  local parts = {}
  for key, value in pairs(env) do
    if value ~= nil and value ~= "" then
      table.insert(parts, string.format("%s=%q", key, tostring(value)))
    end
  end
  if #parts == 0 then
    return script_path
  end
  return string.format("env %s %q", table.concat(parts, " "), script_path)
end

local function resolve_widget_script_path()
  local candidate = CONFIG_DIR .. "/plugins/cortex_widget.sh"
  local file = io.open(candidate, "r")
  if file then
    file:close()
    return candidate
  end
  return CODE_DIR .. "/cortex/barista/cortex_widget.sh"
end

function cortex.create_widget(opts)
  opts = opts or {}
  local position = opts.position or "right"
  local _, icon, color = cortex.get_status()

  local label_font = opts.label_font or ""
  local script_path = opts.script_path or resolve_widget_script_path()
  local script = build_env_script({
    CORTEX_ICON_ON = opts.icon_active or "󰪴",
    CORTEX_ICON_OFF = opts.icon_inactive or "󰪵",
    CORTEX_COLOR_ON = opts.color_active or "0xffa6e3a1",
    CORTEX_COLOR_OFF = opts.color_inactive or "0xff6c7086",
    CORTEX_LABEL_COLOR = opts.label_color or "0xffcdd6f4",
    CORTEX_LABEL_FONT = label_font,
    CORTEX_LABEL_MODE = opts.label_mode or "afs",
    CORTEX_LABEL_PREFIX = opts.label_prefix or "AFS",
    CORTEX_LABEL_ON = opts.label_on or "Cortex",
    CORTEX_LABEL_OFF = opts.label_off or "Off",
    CORTEX_LABEL_TEMPLATE = opts.label_template or "",
    CORTEX_SHOW_LABEL = (opts.show_label == false) and "0" or "1",
    CORTEX_CACHE_TTL = opts.cache_ttl or 60,
    AFS_CONTEXT_ROOT = opts.context_root or "",
  }, script_path)

  local label_drawing = opts.show_label ~= false
  local icon_font = opts.icon_font or { family = "Symbols Nerd Font", size = 14 }

  return {
    name = "cortex",
    position = position,
    icon = {
      string = icon,
      font = icon_font,
      color = color,
    },
    label = { drawing = label_drawing },
    click_script = opts.click_script or (CORTEX_CLI .. " toggle"),
    update_freq = tonumber(opts.update_freq) or 120,
    script = script,
    background = opts.background or { drawing = false },
    padding_left = opts.padding_left or 6,
    padding_right = opts.padding_right or 6,
  }
end

-- Event handlers for sketchybar
cortex.events = {
  -- Called when Cortex starts
  cortex_started = function()
    os.execute("sketchybar --set cortex icon=󰪴 icon.color=0xffa6e3a1")
  end,

  -- Called when Cortex stops
  cortex_stopped = function()
    os.execute("sketchybar --set cortex icon=󰪵 icon.color=0xff6c7086")
  end,
}

return cortex
