-- Control Center Module for Barista
-- A comprehensive control panel for sketchybar, yabai, and workspace
--
-- Combines space layout controls, window operations, service health,
-- and workspace status into a single unified widget on the left side

local control_center = {}

-- Reuse extracted modules instead of duplicating utilities
local shell_utils = require("shell_utils")
local paths_module = require("paths")
local binary_resolver = require("binary_resolver")

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")

-- Delegate to shared modules
local path_exists = shell_utils.file_exists
local shell_quote = shell_utils.shell_quote
local expand_path = paths_module.expand_path
local command_available = shell_utils.command_available
local check_service = shell_utils.check_service
local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()

local function normalize_mode(mode)
  return binary_resolver.normalize_window_manager_mode(mode)
end

local function sketchybar_cmd(args)
  return string.format("%s %s", shell_quote(SKETCHYBAR_BIN), args)
end

local function read_state_modes()
  local ok, json = pcall(require, "json")
  if not ok then return {} end
  local file = io.open(CONFIG_DIR .. "/state.json", "r")
  if not file then return {} end
  local contents = file:read("*a")
  file:close()
  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" or type(data.modes) ~= "table" then
    return {}
  end
  return data.modes
end

local function resolve_scripts_dir()
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then return expand_path(override) end
  local config_scripts = CONFIG_DIR .. "/scripts"
  if path_exists(config_scripts .. "/yabai_control.sh") then return config_scripts end
  local legacy = HOME .. "/.config/scripts"
  if path_exists(legacy .. "/yabai_control.sh") then return legacy end
  return config_scripts
end

local SCRIPTS_DIR = resolve_scripts_dir()

-- check_service and command_available are now in shell_utils

-- normalize_mode delegated to binary_resolver.normalize_window_manager_mode()

local function resolve_window_manager_mode(opts)
  local mode = opts and opts.window_manager_mode
  if not mode or mode == "" then
    mode = os.getenv("BARISTA_WINDOW_MANAGER_MODE")
  end
  if not mode or mode == "" then
    local state = opts and opts.state
    if state and type(state.modes) == "table" then
      mode = state.modes.window_manager
    else
      local modes = read_state_modes()
      mode = modes.window_manager
    end
  end
  return normalize_mode(mode)
end

local function resolve_window_manager_flags(opts)
  local mode = resolve_window_manager_mode(opts)
  local has_yabai = command_available("yabai")
  local has_skhd = command_available("skhd")
  local yabai_running = check_service("yabai")
  local skhd_running = check_service("skhd")
  local enabled = false
  local required = false

  if mode == "disabled" then
    enabled = false
    required = false
  elseif mode == "optional" then
    enabled = yabai_running
    required = false
  elseif mode == "required" then
    enabled = has_yabai
    required = true
  else
    enabled = has_yabai
    required = has_yabai
  end

  return {
    mode = mode,
    enabled = enabled,
    required = required,
    has_yabai = has_yabai,
    has_skhd = has_skhd,
    yabai_running = yabai_running,
    skhd_running = skhd_running,
  }
end

-- Get yabai layout for current space
local function get_current_layout(wm_flags)
  if wm_flags and not wm_flags.enabled then
    return "disabled"
  end
  local handle = io.popen("yabai -m query --spaces --space 2>/dev/null | jq -r '.type // \"unknown\"'")
  if not handle then return "unknown" end
  local result = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  return result
end

-- Get dirty repo count from workspace
local function get_dirty_count()
  local cache_file = HOME .. "/.workspace/cache/dirty.txt"
  local file = io.open(cache_file, "r")
  if not file then return 0 end
  local count = 0
  for _ in file:lines() do
    count = count + 1
  end
  file:close()
  return count
end

-- Status indicators
function control_center.get_status(opts)
  local wm = resolve_window_manager_flags(opts or {})
  local services = {
    yabai = wm.yabai_running,
    skhd = wm.skhd_running,
    sketchybar = check_service("sketchybar"),
    cortex = check_service("cortex") or check_service("Cortex"),
  }

  local all_running = services.sketchybar
  if wm.required then
    all_running = all_running and services.yabai and services.skhd
  end
  local layout = get_current_layout(wm)
  local dirty = get_dirty_count()

  return {
    services = services,
    all_healthy = all_running,
    layout = layout,
    dirty_repos = dirty,
    window_manager = wm,
  }
end

-- Create widget definition
function control_center.create_widget(opts)
  opts = opts or {}
  local status = control_center.get_status(opts)

  -- Icon based on overall health
  local icon = status.all_healthy and "󰕮" or "󰕯"
  local color = status.all_healthy and "0xffa6e3a1" or "0xfff38ba8"

  -- Label shows layout mode prominently
  local label_parts = {}
  if status.layout == "bsp" then
    table.insert(label_parts, "BSP")
  elseif status.layout == "stack" then
    table.insert(label_parts, "Stack")
  elseif status.layout == "float" then
    table.insert(label_parts, "Float")
  elseif status.layout == "disabled" then
    table.insert(label_parts, opts.disabled_label or "Bar")
  else
    table.insert(label_parts, "---")
  end

  local label = table.concat(label_parts, " ")

  local popup_background = opts.popup_background or {
    drawing = true,
    color = "0xf01e1e2e",
    corner_radius = 8,
    border_width = 2,
    border_color = "0xffcdd6f4",
    padding_left = 8,
    padding_right = 8,
  }
  popup_background.drawing = popup_background.drawing ~= false

  return {
    name = "control_center",
    position = opts.position or "left",  -- Left side by default
    icon = {
      string = icon,
      font = opts.icon_font or { family = "Symbols Nerd Font", size = 14 },
      color = color,
      padding_left = 6,
      padding_right = 4,
    },
    label = {
      string = label,
      drawing = opts.show_label ~= false,
      font = opts.label_font or { style = "Bold", size = 11 },
      color = opts.label_color or "0xffcdd6f4",
      padding_left = 2,
      padding_right = 6,
    },
    background = {
      drawing = false,  -- Let bracket handle the background
      color = "0x00000000",
      corner_radius = 4,
      height = opts.height or 22,
    },
    click_script = opts.popup_toggle_script or [[sketchybar --set $NAME popup.drawing=toggle]],
    popup = {
      align = "left",  -- Align popup to left
      background = popup_background,
    },
    update_freq = opts.update_freq or 30,
    script = opts.script_path or (CONFIG_DIR .. "/plugins/control_center.sh"),
  }
end

-- Create popup items with full space layout and window operations
function control_center.create_popup_items(sbar, theme, font_string, settings, opts)
  local items = {}
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local YABAI_CONTROL = SCRIPTS_DIR .. "/yabai_control.sh"
  local TOGGLE_SHORTCUTS = SCRIPTS_DIR .. "/toggle_yabai_shortcuts.sh"
  local TOGGLE_SHORTCUTS_FALLBACK = SCRIPTS_DIR .. "/toggle_shortcuts.sh"
  local wm = resolve_window_manager_flags(opts or {})
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end
  local popup_close = sketchybar_cmd("--set control_center popup.drawing=off")
  local trigger_space_mode_refresh = sketchybar_cmd("--trigger space_mode_refresh")
  local sketchybar_reload = sketchybar_cmd("--reload")
  local function close_after(command)
    if not command or command == "" then
      return popup_close
    end
    return command .. "; " .. popup_close
  end

  -- Header
  table.insert(items, {
    name = "cc.header",
    position = "popup.control_center",
    icon = { string = "󰕮", color = tc("LAVENDER"), drawing = true },
    label = { string = "Control Center", font = font_bold, color = theme.WHITE },
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

  local notice_added = false
  if not wm.enabled then
    local notice_label = nil
    if wm.mode == "disabled" then
      notice_label = "Window manager disabled"
    elseif wm.mode == "required" and not wm.has_yabai then
      notice_label = "Yabai not installed"
    elseif wm.mode == "optional" and wm.has_yabai and not wm.yabai_running then
      notice_label = "Yabai not running"
    end

    if notice_label then
      table.insert(items, {
        name = "cc.window_manager.notice",
        position = "popup.control_center",
        icon = { string = "󰔟", color = tc("YELLOW") },
        label = { string = notice_label, font = font_small },
        ["icon.padding_left"] = 8,
        ["icon.padding_right"] = 6,
        ["label.padding_left"] = 4,
        ["label.padding_right"] = 8,
        click_script = string.format("open %q", CONFIG_DIR .. "/docs/guides/INSTALLATION_GUIDE.md"),
        background = { drawing = false },
      })
      notice_added = true
    end
  end

  if wm.enabled then
    -- Space Layout Section
    table.insert(items, {
      name = "cc.layout_header",
      position = "popup.control_center",
      icon = { string = "", drawing = false },
      label = { string = "Space Layout", font = font_bold, color = tc("BLUE") },
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    })

    local layouts = {
      { id = "float", name = "Float (default)", icon = "󰒄", cmd = CONFIG_DIR .. "/plugins/set_space_mode.sh current float" },
      { id = "bsp", name = "BSP Tiling", icon = "󰆾", cmd = CONFIG_DIR .. "/plugins/set_space_mode.sh current bsp" },
      { id = "stack", name = "Stack Tiling", icon = "󰓩", cmd = CONFIG_DIR .. "/plugins/set_space_mode.sh current stack" },
    }

    for _, layout in ipairs(layouts) do
      table.insert(items, {
        name = "cc.layout." .. layout.id,
        position = "popup.control_center",
        icon = { string = layout.icon, color = tc("SAPPHIRE") },
        label = { string = layout.name, font = font_small },
        ["icon.padding_left"] = 8,
        ["icon.padding_right"] = 6,
        ["label.padding_left"] = 4,
        ["label.padding_right"] = 8,
        click_script = string.format("%s; %s; %s", layout.cmd, trigger_space_mode_refresh, popup_close),
        background = { drawing = false },
      })
    end

    -- Separator
    table.insert(items, {
      name = "cc.sep1",
      position = "popup.control_center",
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
      ["label.padding_left"] = 8,
      background = { drawing = false },
    })

    -- Layout Operations Section
    table.insert(items, {
      name = "cc.layout_ops_header",
      position = "popup.control_center",
      icon = { string = "", drawing = false },
      label = { string = "Layout Ops", font = font_bold, color = tc("GREEN") },
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    })

    local layout_ops = {
      { id = "balance", name = "Balance Windows", icon = "󰓅", cmd = YABAI_CONTROL .. " balance" },
      { id = "rotate", name = "Rotate Layout", icon = "󰑞", cmd = YABAI_CONTROL .. " space-rotate" },
      { id = "toggle", name = "Toggle BSP/Stack", icon = "󱂬", cmd = YABAI_CONTROL .. " toggle-layout" },
      { id = "flipx", name = "Flip Horizontal", icon = "󰯌", cmd = YABAI_CONTROL .. " space-mirror-x" },
      { id = "flipy", name = "Flip Vertical", icon = "󰯎", cmd = YABAI_CONTROL .. " space-mirror-y" },
    }

    for _, op in ipairs(layout_ops) do
      table.insert(items, {
        name = "cc.layout_ops." .. op.id,
        position = "popup.control_center",
        icon = { string = op.icon, color = theme.TEAL },
        label = { string = op.name, font = font_small },
        ["icon.padding_left"] = 8,
        ["icon.padding_right"] = 6,
        ["label.padding_left"] = 4,
        ["label.padding_right"] = 8,
        click_script = close_after(op.cmd),
        background = { drawing = false },
      })
    end

    -- Separator
    table.insert(items, {
      name = "cc.sep2",
      position = "popup.control_center",
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
      ["label.padding_left"] = 8,
      background = { drawing = false },
    })

    -- Yabai Shortcuts Toggle
    local shortcuts_running = wm.skhd_running
    local shortcuts_on_label = "Yabai Shortcuts: On"
    local shortcuts_off_label = "Yabai Shortcuts: Off"
    local shortcuts_label = shortcuts_running and shortcuts_on_label or shortcuts_off_label
    local shortcuts_color = shortcuts_running and tc("GREEN") or tc("RED")
    local toggle_script = SCRIPTS_DIR .. "/toggle_yabai_shortcuts.sh"
    if not path_exists(toggle_script) then
      toggle_script = SCRIPTS_DIR .. "/toggle_shortcuts.sh"
    end
    local toggle_action = path_exists(toggle_script) and (shell_quote(toggle_script) .. " toggle")
      or ("bash " .. shell_quote(CONFIG_DIR .. "/bin/open_control_panel.sh"))
    local update_action = string.format(
      "if pgrep -x skhd >/dev/null 2>&1; then %s --set $NAME label='%s' icon.color=%s; else %s --set $NAME label='%s' icon.color=%s; fi",
      shell_quote(SKETCHYBAR_BIN),
      shortcuts_on_label,
      tc("GREEN"),
      shell_quote(SKETCHYBAR_BIN),
      shortcuts_off_label,
      tc("RED")
    )
    table.insert(items, {
      name = "cc.yabai.shortcuts",
      position = "popup.control_center",
      icon = { string = "󰌌", color = shortcuts_color },
      label = { string = shortcuts_label, font = font_small },
      ["icon.padding_left"] = 8,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      click_script = string.format("%s; %s; %s", toggle_action, update_action, popup_close),
      background = { drawing = false },
    })
  end

  if wm.enabled or notice_added then
    -- Separator
    table.insert(items, {
      name = "cc.sep3",
      position = "popup.control_center",
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
      ["label.padding_left"] = 8,
      background = { drawing = false },
    })
  end

  -- Services Section
  table.insert(items, {
    name = "cc.services_header",
    position = "popup.control_center",
    icon = { string = "", drawing = false },
    label = { string = "Services", font = font_bold, color = tc("YELLOW") },
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

  local services = {}
  if wm.mode ~= "disabled" then
    if wm.has_yabai or wm.required then
      table.insert(services, {
        name = "Yabai",
        proc = "yabai",
        restart = shell_quote(YABAI_CONTROL) .. " restart",
      })
    end
    if wm.has_skhd or wm.required then
      local skhd_restart = nil
      if path_exists(TOGGLE_SHORTCUTS) then
        skhd_restart = shell_quote(TOGGLE_SHORTCUTS) .. " restart"
      elseif path_exists(TOGGLE_SHORTCUTS_FALLBACK) then
        skhd_restart = string.format(
          "%s off; %s on",
          shell_quote(TOGGLE_SHORTCUTS_FALLBACK),
          shell_quote(TOGGLE_SHORTCUTS_FALLBACK)
        )
      else
        skhd_restart = "skhd --restart-service"
      end
      table.insert(services, { name = "skhd", proc = "skhd", restart = skhd_restart })
    end
  end
  table.insert(services, { name = "SketchyBar", proc = "sketchybar", restart = sketchybar_reload })

  for _, svc in ipairs(services) do
    local running = nil
    if svc.proc == "yabai" then
      running = wm.yabai_running
    elseif svc.proc == "skhd" then
      running = wm.skhd_running
    else
      running = check_service(svc.proc)
    end
    local status_icon = running and "●" or "○"
    local status_color = running and tc("GREEN") or tc("RED")
    table.insert(items, {
      name = "cc.svc." .. svc.name:lower():gsub(" ", ""),
      position = "popup.control_center",
      icon = { string = status_icon, color = status_color },
      label = { string = svc.name, font = font_small },
      ["icon.padding_left"] = 10,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      click_script = close_after(svc.restart),
      background = { drawing = false },
    })
  end

  -- Separator
  table.insert(items, {
    name = "cc.sep4",
    position = "popup.control_center",
    icon = { drawing = false },
    label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
    ["label.padding_left"] = 8,
    background = { drawing = false },
  })

  -- Process Tools Section
  table.insert(items, {
    name = "cc.process_header",
    position = "popup.control_center",
    icon = { string = "", drawing = false },
    label = { string = "Process Tools", font = font_bold, color = tc("TEAL") },
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

  local process_manager = SCRIPTS_DIR .. "/process_manager.sh"
  local process_manager_cmd = path_exists(process_manager) and shell_quote(process_manager) or nil

  table.insert(items, {
    name = "cc.process.activity",
    position = "popup.control_center",
    icon = { string = "󰨇", color = tc("GREEN") },
    label = { string = "Activity Monitor", font = font_small },
    ["icon.padding_left"] = 8,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    click_script = close_after("open -a 'Activity Monitor'"),
    background = { drawing = false },
  })

  if process_manager_cmd then
    table.insert(items, {
      name = "cc.process.cleanup_mounts",
      position = "popup.control_center",
      icon = { string = "󰅗", color = tc("YELLOW") },
      label = { string = "Clean stale mounts", font = font_small },
      ["icon.padding_left"] = 8,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      click_script = close_after(process_manager_cmd .. " cleanup-mounts"),
      background = { drawing = false },
    })
  end

  -- Separator
  table.insert(items, {
    name = "cc.sep5",
    position = "popup.control_center",
    icon = { drawing = false },
    label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
    ["label.padding_left"] = 8,
    background = { drawing = false },
  })

  -- Workspace Status
  local dirty = get_dirty_count()
  table.insert(items, {
    name = "cc.workspace",
    position = "popup.control_center",
    icon = { string = "", color = dirty > 0 and tc("YELLOW") or tc("GREEN") },
    label = { string = dirty > 0 and string.format("%d dirty repos", dirty) or "Workspace clean", font = font_small },
    ["icon.padding_left"] = 8,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    click_script = "open ~/src",
    background = { drawing = false },
  })

  return items
end

return control_center
