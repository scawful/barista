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
local DEFAULT_ITEM_NAME = "control_center"

local function normalize_mode(mode)
  return binary_resolver.normalize_window_manager_mode(mode)
end

local function sketchybar_cmd(args)
  return string.format("%s %s", shell_quote(SKETCHYBAR_BIN), args)
end

local function resolve_config_dir(opts)
  local override = opts and opts.config_dir
  if override and override ~= "" then
    return expand_path(override)
  end
  return CONFIG_DIR
end

local function read_state_modes(config_dir)
  local ok, json = pcall(require, "json")
  if not ok then return {} end
  local file = io.open((config_dir or CONFIG_DIR) .. "/state.json", "r")
  if not file then return {} end
  local contents = file:read("*a")
  file:close()
  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" or type(data.modes) ~= "table" then
    return {}
  end
  return data.modes
end

local function resolve_scripts_dir(opts)
  local override = opts and opts.scripts_dir
  if override and override ~= "" then
    return expand_path(override)
  end
  return paths_module.resolve_scripts_dir(resolve_config_dir(opts), opts and opts.state)
end

-- check_service and command_available are now in shell_utils

-- normalize_mode delegated to binary_resolver.normalize_window_manager_mode()

local function resolve_item_name(opts)
  local name = opts and (opts.item_name or opts.name)
  if name and name ~= "" then
    return name
  end
  local env_name = os.getenv("BARISTA_CONTROL_CENTER_ITEM_NAME")
  if env_name and env_name ~= "" then
    return env_name
  end
  local state = opts and opts.state
  local integrations = state and state.integrations
  local control_center_state = type(integrations) == "table" and integrations.control_center or nil
  local state_name = type(control_center_state) == "table" and (control_center_state.item_name or control_center_state.name) or nil
  if state_name and state_name ~= "" then
    return state_name
  end
  return DEFAULT_ITEM_NAME
end

local function resolve_popup_position(opts)
  return "popup." .. resolve_item_name(opts)
end

function control_center.get_item_name(opts)
  return resolve_item_name(opts)
end

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
      local modes = read_state_modes(resolve_config_dir(opts))
      mode = modes.window_manager
    end
  end
  return normalize_mode(mode)
end

local function compute_window_manager_flags(opts)
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

local function resolve_window_manager_flags(opts)
  local flags = compute_window_manager_flags(opts)
  local override = opts and opts.window_manager_flags
  if type(override) == "table" then
    for key, value in pairs(override) do
      flags[key] = value
    end
    flags.mode = normalize_mode(flags.mode)
  end
  return flags
end

-- Get yabai layout for current space
local function get_current_layout(wm_flags, opts)
  local override = opts and opts.layout
  if type(override) == "string" and override ~= "" then
    return override
  end
  if wm_flags and not wm_flags.enabled then
    return "disabled"
  end
  local handle = io.popen("yabai -m query --spaces --space 2>/dev/null | jq -r '.type // \"unknown\"'")
  if not handle then return "unknown" end
  local result = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  return result
end

-- Status indicators
function control_center.get_status(opts)
  local wm = resolve_window_manager_flags(opts or {})
  local services = {
    yabai = wm.yabai_running,
    skhd = wm.skhd_running,
    sketchybar = check_service("sketchybar"),
  }

  local all_running = services.sketchybar
  if wm.required then
    all_running = all_running and services.yabai and services.skhd
  end
  local layout = get_current_layout(wm, opts)

  return {
    services = services,
    all_healthy = all_running,
    layout = layout,
    window_manager = wm,
  }
end

-- Create widget definition
function control_center.create_widget(opts)
  opts = opts or {}
  local status = opts.status or control_center.get_status(opts)
  local config_dir = resolve_config_dir(opts)

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
    name = resolve_item_name(opts),
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
    script = opts.script_path or (config_dir .. "/plugins/control_center.sh"),
  }
end

-- Create popup items with full space layout and window operations
function control_center.create_popup_items(sbar, theme, font_string, settings, opts)
  opts = opts or {}
  local items = {}
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local config_dir = resolve_config_dir(opts)
  local scripts_dir = resolve_scripts_dir(opts)
  local item_name = resolve_item_name(opts)
  local popup_position = resolve_popup_position(opts)
  local YABAI_CONTROL = scripts_dir .. "/yabai_control.sh"
  local TOGGLE_SHORTCUTS = scripts_dir .. "/toggle_yabai_shortcuts.sh"
  local TOGGLE_SHORTCUTS_FALLBACK = scripts_dir .. "/toggle_shortcuts.sh"
  local wm = resolve_window_manager_flags(opts)
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end
  local function shell_command(path, args)
    if not path or path == "" then
      return args or ""
    end
    if args and args ~= "" then
      return shell_quote(path) .. " " .. args
    end
    return shell_quote(path)
  end
  local popup_close = sketchybar_cmd(string.format("--set %s popup.drawing=off", shell_quote(item_name)))
  local trigger_space_mode_refresh = sketchybar_cmd("--trigger space_mode_refresh")
  local function close_after(command)
    if not command or command == "" then
      return popup_close
    end
    return command .. "; " .. popup_close
  end

  -- Header
  table.insert(items, {
    name = "cc.header",
    position = popup_position,
    icon = { string = "󰕮", color = tc("LAVENDER"), drawing = true },
    label = { string = "Control Center", font = font_bold, color = theme.WHITE },
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

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
        position = popup_position,
        icon = { string = "󰔟", color = tc("YELLOW") },
        label = { string = notice_label, font = font_small },
        ["icon.padding_left"] = 8,
        ["icon.padding_right"] = 6,
        ["label.padding_left"] = 4,
        ["label.padding_right"] = 8,
        click_script = string.format("open %q", config_dir .. "/docs/guides/INSTALLATION_GUIDE.md"),
        background = { drawing = false },
      })
    end
  end

  if wm.enabled then
    -- Space Layout Section
    table.insert(items, {
      name = "cc.layout_header",
      position = popup_position,
      icon = { string = "", drawing = false },
      label = { string = "Space Layout", font = font_bold, color = tc("BLUE") },
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    })

    local layouts = {
      { id = "float", name = "Float (default)", icon = "󰒄", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current float") },
      { id = "bsp", name = "BSP Tiling", icon = "󰆾", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current bsp") },
      { id = "stack", name = "Stack Tiling", icon = "󰓩", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current stack") },
    }

    for _, layout in ipairs(layouts) do
      table.insert(items, {
        name = "cc.layout." .. layout.id,
        position = popup_position,
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
      position = popup_position,
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
      ["label.padding_left"] = 8,
      background = { drawing = false },
    })

    -- Layout Operations Section
    table.insert(items, {
      name = "cc.layout_ops_header",
      position = popup_position,
      icon = { string = "", drawing = false },
      label = { string = "Layout Ops", font = font_bold, color = tc("GREEN") },
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    })

    local layout_ops = {
      { id = "balance", name = "Balance Windows", icon = "󰓅", cmd = shell_command(YABAI_CONTROL, "balance") },
      { id = "rotate", name = "Rotate Layout", icon = "󰑞", cmd = shell_command(YABAI_CONTROL, "space-rotate") },
      { id = "toggle", name = "Toggle BSP/Stack", icon = "󱂬", cmd = shell_command(YABAI_CONTROL, "toggle-layout") },
      { id = "flipx", name = "Flip Horizontal", icon = "󰯌", cmd = shell_command(YABAI_CONTROL, "space-mirror-x") },
      { id = "flipy", name = "Flip Vertical", icon = "󰯎", cmd = shell_command(YABAI_CONTROL, "space-mirror-y") },
    }

    for _, op in ipairs(layout_ops) do
      table.insert(items, {
        name = "cc.layout_ops." .. op.id,
        position = popup_position,
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
      position = popup_position,
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
    local toggle_script = scripts_dir .. "/toggle_yabai_shortcuts.sh"
    if not path_exists(toggle_script) then
      toggle_script = scripts_dir .. "/toggle_shortcuts.sh"
    end
    local toggle_action = path_exists(toggle_script) and shell_command(toggle_script, "toggle")
      or ("bash " .. shell_quote(config_dir .. "/bin/open_control_panel.sh"))
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
      position = popup_position,
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

  return items
end

return control_center
