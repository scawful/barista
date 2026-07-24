-- Control Center Module for Barista
-- A compact control panel for SketchyBar and yabai behavior.
--
-- Keeps window-manager modes, space layouts, window operations, and app
-- defaults reachable from one left-side widget.

local control_center = {}

-- Reuse extracted modules instead of duplicating utilities
local shell_utils = require("shell_utils")
local paths_module = require("paths")
local binary_resolver = require("binary_resolver")
local ui = require("ui_builder")

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

local WINDOW_MANAGER_FLAG_KEYS = {
  "mode",
  "enabled",
  "required",
  "has_yabai",
  "has_skhd",
  "yabai_running",
  "skhd_running",
}

local function complete_window_manager_flags(override)
  if type(override) ~= "table" then
    return false
  end
  for _, key in ipairs(WINDOW_MANAGER_FLAG_KEYS) do
    if override[key] == nil then
      return false
    end
  end
  return true
end

local function copy_window_manager_flags(source)
  local flags = {}
  for key, value in pairs(source) do
    flags[key] = value
  end
  flags.mode = normalize_mode(flags.mode)
  return flags
end

local function resolve_window_manager_flags(opts)
  local override = opts and opts.window_manager_flags
  if complete_window_manager_flags(override) then
    return copy_window_manager_flags(override)
  end

  local flags = compute_window_manager_flags(opts)
  if type(override) == "table" then
    for key, value in pairs(override) do
      flags[key] = value
    end
    flags.mode = normalize_mode(flags.mode)
  end
  return flags
end

-- Dynamic layout discovery belongs to the bounded post-config plugin refresh.
-- Config construction only consumes an explicit cached/seeded value so a
-- stalled yabai socket cannot block the entire bar from loading.
local function get_current_layout(wm_flags, opts)
  local override = opts and opts.layout
  if type(override) == "string" and override ~= "" then
    return override
  end
  if wm_flags and not wm_flags.enabled then
    return "disabled"
  end
  return "unknown"
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
  local submenu_parents = {}
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local config_dir = resolve_config_dir(opts)
  local scripts_dir = resolve_scripts_dir(opts)
  local item_name = resolve_item_name(opts)
  local more_name = "cc.more"
  local YABAI_CONTROL = scripts_dir .. "/yabai_control.sh"
  local wm = resolve_window_manager_flags(opts)
  local style = {
    font_small = font_small,
    font_header = font_bold,
    item_corner_radius = 6,
    padding = { icon_left = 8, icon_right = 6, label_left = 4, label_right = 8 },
    label_color = theme.WHITE,
    separator_color = "0x40cdd6f4",
  }
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
  local trigger_space_mode_refresh = sketchybar_cmd("--trigger space_mode_refresh")
  local function close_after(command, parent)
    if parent and parent ~= item_name then
      return ui.close_after_all({ parent, item_name }, command, {
        sketchybar_bin = SKETCHYBAR_BIN,
      })
    end
    return ui.close_after(item_name, command, { sketchybar_bin = SKETCHYBAR_BIN })
  end
  local function close_root_after(command)
    if wm.enabled then
      return ui.close_after_all({ more_name, item_name }, command, {
        sketchybar_bin = SKETCHYBAR_BIN,
      })
    end
    return close_after(command)
  end

  local function normalize_label(item, label, font, color)
    item.label = { string = label or "", font = font or font_small, color = color }
    return item
  end

  local function normalize_icon(item, icon, color, drawing)
    if type(icon) == "table" then
      item.icon = icon
    else
      item.icon = { string = icon or "", color = color, drawing = drawing }
    end
    return item
  end

  local function add_header(name, label, color, icon, icon_color, parent)
    local built = {}
    ui.header(built, parent or item_name, name, label, {
      style = style,
      font = font_bold,
      color = color,
      icon = icon and { string = icon, color = icon_color or color, drawing = true } or { string = "", drawing = false },
      background_drawing = false,
    })
    local item = built[1]
    normalize_label(item, label, font_bold, color)
    normalize_icon(item, icon or "", icon_color or color, icon ~= nil)
    item["label.padding_left"] = icon and 4 or 8
    item["label.padding_right"] = 8
    item["icon.padding_left"] = icon and 6 or 8
    item["icon.padding_right"] = 6
    item.background = { drawing = false }
    table.insert(items, item)
  end

  local function add_separator(name, parent)
    local built = {}
    ui.separator(built, parent or item_name, name, {
      style = style,
      font = font_small,
      color = "0x40cdd6f4",
    })
    local item = built[1]
    normalize_label(item, "───────────────", font_small, "0x40cdd6f4")
    item.icon = { drawing = false }
    item["label.padding_left"] = 8
    item.background = { drawing = false }
    table.insert(items, item)
  end

  local function add_row(name, row, parent)
    row = row or {}
    local built = {}
    ui.row(built, parent or item_name, name, {
      style = style,
      icon = { string = row.icon or "", color = row.color },
      label = row.label or row.name or "",
      click_script = row.click_script,
      action = row.action,
      sketchybar_bin = SKETCHYBAR_BIN,
      hover = row.hover,
      label_color = row.label_color,
    })
    local item = built[1]
    normalize_icon(item, row.icon or "", row.color, row.icon_drawing)
    normalize_label(item, row.label or row.name or "", row.font or font_small, row.label_color)
    item["icon.padding_left"] = 8
    item["icon.padding_right"] = 6
    item["label.padding_left"] = 4
    item["label.padding_right"] = 8
    item.background = row.background or { drawing = false }
    table.insert(items, item)
  end

  local function add_submenu(name, label, icon, color)
    local built = {}
    ui.submenu(built, item_name, name, {
      style = style,
      icon = { string = icon, color = color },
      label = label,
      font = font_small,
      label_color = style.label_color,
      popup_background = opts.popup_background,
      sketchybar_bin = SKETCHYBAR_BIN,
      popup_manager_script = opts.popup_manager_script,
      popup_topology_token = opts.popup_topology_token,
    })
    local item = built[1]
    normalize_icon(item, icon, color, true)
    normalize_label(item, item.label or label, font_small, style.label_color)
    item["icon.padding_left"] = 8
    item["icon.padding_right"] = 6
    item["label.padding_left"] = 4
    item["label.padding_right"] = 8
    item.background = { drawing = false }
    table.insert(items, item)
    table.insert(submenu_parents, name)
  end

  local function add_extension_rows(prefix, rows)
    if type(rows) ~= "table" or #rows == 0 then
      return
    end
    add_separator(prefix .. ".sep")
    add_header(prefix .. ".header", "Desk", tc("TEAL"))
    for _, row in ipairs(rows) do
      if row.action and row.action ~= "" then
        add_row(prefix .. "." .. row.id, {
          icon = row.icon or "󰐕",
          color = row.icon_color or tc("TEAL"),
          label = row.label or row.id,
          label_color = row.label_color,
          click_script = close_after(row.action),
        })
      end
    end
  end

  add_header("cc.header", "Control Center", theme.WHITE, "󰕮", tc("LAVENDER"))
  add_header("cc.mode_header", "Mode", tc("MAUVE", "LAVENDER"))

  local function mode_label(id, label)
    if wm.mode == id then return "● " .. label end
    return "○ " .. label
  end
  local mode_rows = {
    { id = "required", label = "Yabai On", icon = "󰆾", color = tc("GREEN"), cmd = shell_command(YABAI_CONTROL, "wm-mode required") },
    { id = "optional", label = "Auto If Running", icon = "󰐊", color = tc("SAPPHIRE"), cmd = shell_command(YABAI_CONTROL, "wm-mode optional") },
    { id = "disabled", label = "Manual Bar", icon = "󰒄", color = tc("YELLOW"), cmd = shell_command(YABAI_CONTROL, "wm-mode disabled") },
  }
  for _, row in ipairs(mode_rows) do
    add_row("cc.mode." .. row.id, {
      icon = row.icon,
      color = row.color,
      label = mode_label(row.id, row.label),
      click_script = close_root_after(row.cmd),
    })
  end

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
      add_row("cc.window_manager.notice", {
        icon = "󰔟",
        color = tc("YELLOW"),
        label = notice_label,
        click_script = string.format("open %q", config_dir .. "/docs/guides/INSTALLATION_GUIDE.md"),
      })
    end
    add_extension_rows("cc.extension", opts.extension_items)
  end

  if wm.enabled then
    add_header("cc.layout_header", "Space Layout", tc("BLUE"))

    local layouts = {
      { id = "float", name = "Float / Manual", icon = "󰒄", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current float") },
      { id = "bsp", name = "BSP Tiling", icon = "󰆾", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current bsp") },
      { id = "stack", name = "Stack Tiling", icon = "󰓩", cmd = shell_command(config_dir .. "/plugins/set_space_mode.sh", "current stack") },
    }
    for _, layout in ipairs(layouts) do
      add_row("cc.layout." .. layout.id, {
        icon = layout.icon,
        color = tc("SAPPHIRE"),
        label = layout.name,
        click_script = close_root_after(string.format("%s; %s", layout.cmd, trigger_space_mode_refresh)),
      })
    end

    add_separator("cc.sep1")
    add_submenu(more_name, "More Layout Controls", "󰒓", tc("YELLOW"))
    add_header("cc.layout_ops_header", "Layout Ops", tc("GREEN"), nil, nil, more_name)

    local layout_ops = {
      { id = "balance", name = "Balance Windows", icon = "󰓅", cmd = shell_command(YABAI_CONTROL, "balance") },
      { id = "rotate", name = "Rotate Layout", icon = "󰑞", cmd = shell_command(YABAI_CONTROL, "space-rotate") },
      { id = "toggle", name = "Toggle BSP/Stack", icon = "󱂬", cmd = shell_command(YABAI_CONTROL, "toggle-layout") },
      { id = "flipx", name = "Flip Horizontal", icon = "󰯌", cmd = shell_command(YABAI_CONTROL, "space-mirror-x") },
      { id = "flipy", name = "Flip Vertical", icon = "󰯎", cmd = shell_command(YABAI_CONTROL, "space-mirror-y") },
    }
    for _, op in ipairs(layout_ops) do
      add_row("cc.layout_ops." .. op.id, {
        icon = op.icon,
        color = theme.TEAL,
        label = op.name,
        click_script = close_after(op.cmd, more_name),
      }, more_name)
    end

    add_separator("cc.sep2", more_name)
    add_header("cc.defaults_header", "Current App Defaults", tc("PEACH"), nil, nil, more_name)

    local default_ops = {
      { id = "float", name = "Default App: Float", icon = "󰒄", cmd = shell_command(YABAI_CONTROL, "app-default-current float") },
      { id = "tile", name = "Default App: Tile", icon = "󰆾", cmd = shell_command(YABAI_CONTROL, "app-default-current tile") },
      { id = "unset", name = "Unset App Default", icon = "󰅖", cmd = shell_command(YABAI_CONTROL, "app-default-current unset") },
    }
    for _, op in ipairs(default_ops) do
      add_row("cc.defaults." .. op.id, {
        icon = op.icon,
        color = op.id == "unset" and tc("RED") or tc("PEACH"),
        label = op.name,
        click_script = close_after(op.cmd, more_name),
      }, more_name)
    end

    local shortcuts_running = wm.skhd_running
    local shortcuts_on_label = "Shortcuts: On"
    local shortcuts_off_label = "Shortcuts: Off"
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
    add_row("cc.yabai.shortcuts", {
      icon = "󰌌",
      color = shortcuts_color,
      label = shortcuts_label,
      click_script = close_root_after(string.format("%s; %s", toggle_action, update_action)),
    })
  end

  return items, { submenu_parents = submenu_parents }
end

return control_center
