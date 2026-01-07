-- Cortex Integration Module for Barista
-- The brain layer that orchestrates AFS, Barista, and halext-org
--
-- Install: Copy to ~/.config/sketchybar/modules/integrations/cortex.lua
-- Or symlink: ln -sf ~/src/lab/cortex/barista/cortex.lua ~/.config/sketchybar/modules/integrations/
-- (repo may live at ~/src/cortex or ~/src/lab/cortex)

local cortex = {}

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
local DEFAULT_CODE_DIR = HOME .. "/src"

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function path_exists(path, want_dir)
  if not path or path == "" then
    return false
  end
  if want_dir then
    local ok = os.execute(string.format("test -d %q", path))
    return ok == true or ok == 0
  end
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function path_is_executable(path)
  if not path or path == "" then
    return false
  end
  local ok = os.execute(string.format("test -x %q", path))
  return ok == true or ok == 0
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function command_path(command)
  local handle = io.popen(string.format("command -v %q 2>/dev/null", command))
  if not handle then
    return nil
  end
  local result = handle:read("*a") or ""
  handle:close()
  result = result:gsub("%s+$", "")
  if result == "" then
    return nil
  end
  return result
end

local function resolve_code_dir(ctx)
  local candidate = (ctx and ctx.paths and ctx.paths.code_dir)
    or os.getenv("BARISTA_CODE_DIR")
    or DEFAULT_CODE_DIR
  candidate = expand_path(candidate)
  local fallback = DEFAULT_CODE_DIR
  if candidate and candidate:match("/Code/?$") and path_exists(fallback, true) then
    return fallback
  end
  if candidate and not path_exists(candidate, true) and path_exists(fallback, true) then
    return fallback
  end
  if candidate and not path_exists(candidate .. "/lab", true) and path_exists(fallback .. "/lab", true) then
    return fallback
  end
  return candidate or fallback
end

local function resolve_repo_path(code_dir)
  if not code_dir or code_dir == "" then
    return nil
  end
  local lab_path = code_dir .. "/lab/cortex"
  if path_exists(lab_path, true) then
    return lab_path
  end
  local root_path = code_dir .. "/cortex"
  if path_exists(root_path, true) then
    return root_path
  end
  return lab_path
end

local function resolve_cli_path(ctx)
  local override = os.getenv("CORTEX_CLI") or os.getenv("CORTEX_CLI_PATH")
  if override and override ~= "" then
    override = expand_path(override)
    if path_is_executable(override) then
      return override
    end
  end

  local resolved = command_path("cortex-cli")
  if resolved then
    return resolved
  end

  local code_dir = resolve_code_dir(ctx)
  local candidates = {
    code_dir .. "/lab/cortex/bin/cortex-cli",
    code_dir .. "/cortex/bin/cortex-cli",
    HOME .. "/.local/bin/cortex-cli",
  }
  for _, candidate in ipairs(candidates) do
    if path_is_executable(candidate) then
      return candidate
    end
  end

  return nil
end

local function resolve_bin_path(ctx)
  local override = os.getenv("CORTEX_BINARY") or os.getenv("CORTEX_BIN")
  if override and override ~= "" then
    override = expand_path(override)
    if path_is_executable(override) then
      return override
    end
  end

  local resolved = command_path("cortex")
  if resolved then
    return resolved
  end

  local code_dir = resolve_code_dir(ctx)
  local candidates = {
    code_dir .. "/lab/cortex/bin/cortex",
    code_dir .. "/cortex/bin/cortex",
    HOME .. "/.local/bin/cortex",
  }
  for _, candidate in ipairs(candidates) do
    if path_is_executable(candidate) then
      return candidate
    end
  end

  return nil
end

-- Configuration
cortex.config = {
  cli_path = nil,
  bin_path = nil,
  repo_path = nil,
  code_dir = nil,
}

function cortex.refresh_config(ctx)
  local code_dir = resolve_code_dir(ctx)
  cortex.config.code_dir = code_dir
  cortex.config.cli_path = resolve_cli_path(ctx) or "cortex-cli"
  cortex.config.bin_path = resolve_bin_path(ctx)
  cortex.config.repo_path = resolve_repo_path(code_dir)
end

cortex.refresh_config()

-- Notification names (match CortexNotifications.swift)
cortex.notifications = {
  toggle = "com.scawful.cortex.dashboard.toggle",
  refresh = "com.scawful.cortex.refresh",
  hub = "com.scawful.cortex.hub.open",
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
    return "running", "󰪴", "0xffa6e3a1"  -- icon, green
  else
    return "stopped", "󰪵", "0xff6c7086"  -- icon, gray
  end
end

-- Start Cortex
function cortex.start()
  if cortex.is_running() then
    return true, "Already running"
  end

  cortex.refresh_config()
  local bin = cortex.config.bin_path
  if path_is_executable(bin) then
    os.execute(string.format("%q &", bin))
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

function cortex.open_hub()
  if not cortex.is_running() then
    cortex.start()
    os.execute("sleep 0.4")
  end
  post_notification(cortex.notifications.hub)
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
  cortex.refresh_config(ctx)
  local cli_path = cortex.config.cli_path or "cortex-cli"
  local items = {}
  local running = cortex.is_running()
  local status_icon = running and "󰪴" or "󰪵"
  local status_color = running and "0xffa6e3a1" or "0xff6c7086"

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
    shell_action = string.format("%s toggle", shell_quote(cli_path)),
  })

  -- Open Hub
  table.insert(items, {
    type = "item",
    name = "cortex.hub",
    icon = "󰣖",
    label = "Open Cortex Hub",
    action = function()
      cortex.open_hub()
    end,
    shell_action = string.format("%s hub", shell_quote(cli_path)),
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
      shell_action = string.format("%s refresh", shell_quote(cli_path)),
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
      shell_action = string.format("%s restart", shell_quote(cli_path)),
    })

    table.insert(items, {
      type = "item",
      name = "cortex.stop",
      icon = "󰓛",
      label = "Stop Cortex",
      action = function()
        cortex.stop()
      end,
      shell_action = string.format("%s stop", shell_quote(cli_path)),
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
      shell_action = string.format("%s start", shell_quote(cli_path)),
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
  local repo_path = cortex.config.repo_path or resolve_repo_path(resolve_code_dir())
  if repo_path then
    return repo_path .. "/barista/cortex_widget.sh"
  end
  return candidate
end

function cortex.create_widget(opts)
  opts = opts or {}
  cortex.refresh_config(opts.ctx)
  local cli_path = cortex.config.cli_path or "cortex-cli"
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
    click_script = opts.click_script or string.format("%s toggle", shell_quote(cli_path)),
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
