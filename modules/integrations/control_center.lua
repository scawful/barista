-- Control Center Module for Barista
-- A comprehensive control panel for sketchybar, yabai, and workspace
--
-- Combines space layout controls, window operations, service health,
-- and workspace status into a single unified widget on the left side

local control_center = {}

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")

local function path_exists(path)
  if not path or path == "" then
    return false
  end
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function read_state_scripts_dir()
  local ok, json = pcall(require, "json")
  if not ok then
    return nil
  end

  local file = io.open(CONFIG_DIR .. "/state.json", "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()

  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end

  if type(data.paths) ~= "table" then
    return nil
  end

  local candidate = data.paths.scripts_dir or data.paths.scripts
  return expand_path(candidate)
end

local function scripts_available(path)
  if not path or path == "" then
    return false
  end
  if path_exists(path .. "/yabai_control.sh") then
    return true
  end
  if path_exists(path .. "/toggle_shortcuts.sh") then
    return true
  end
  if path_exists(path .. "/toggle_yabai_shortcuts.sh") then
    return true
  end
  return false
end

local function resolve_scripts_dir()
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end

  local state_override = read_state_scripts_dir()
  if state_override and state_override ~= "" and scripts_available(state_override) then
    return state_override
  end

  local config_scripts = CONFIG_DIR .. "/scripts"
  if scripts_available(config_scripts) then
    return config_scripts
  end

  local legacy_scripts = HOME .. "/.config/scripts"
  if scripts_available(legacy_scripts) then
    return legacy_scripts
  end

  return config_scripts
end

local SCRIPTS_DIR = resolve_scripts_dir()

-- Check service status
local function check_service(name)
  local handle = io.popen(string.format("pgrep -x %s >/dev/null 2>&1 && echo 1 || echo 0", name))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Get yabai layout for current space
local function get_current_layout()
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
function control_center.get_status()
  local services = {
    yabai = check_service("yabai"),
    skhd = check_service("skhd"),
    sketchybar = check_service("sketchybar"),
    cortex = check_service("cortex") or check_service("Cortex"),
  }

  local all_running = services.yabai and services.skhd and services.sketchybar
  local layout = get_current_layout()
  local dirty = get_dirty_count()

  return {
    services = services,
    all_healthy = all_running,
    layout = layout,
    dirty_repos = dirty,
  }
end

-- Create widget definition
function control_center.create_widget(opts)
  opts = opts or {}
  local status = control_center.get_status()

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
  else
    table.insert(label_parts, "---")
  end

  local label = table.concat(label_parts, " ")

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
    click_script = [[sketchybar --set $NAME popup.drawing=toggle]],
    popup = {
      align = "left",  -- Align popup to left
      background = {
        drawing = true,
        color = "0xf01e1e2e",
        corner_radius = 8,
        border_width = 2,
        border_color = "0xffcdd6f4",
        padding_left = 8,
        padding_right = 8,
      },
    },
    update_freq = opts.update_freq or 30,
    script = opts.script_path or (CONFIG_DIR .. "/plugins/control_center.sh"),
  }
end

-- Create popup items with full space layout and window operations
function control_center.create_popup_items(sbar, theme, font_string, settings)
  local items = {}
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local YABAI_CONTROL = SCRIPTS_DIR .. "/yabai_control.sh"

  -- Header
  table.insert(items, {
    name = "cc.header",
    position = "popup.control_center",
    icon = { string = "󰕮", color = theme.LAVENDER, drawing = true },
    label = { string = "Control Center", font = font_bold, color = theme.WHITE },
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

  -- Space Layout Section
  table.insert(items, {
    name = "cc.layout_header",
    position = "popup.control_center",
    icon = { string = "", drawing = false },
    label = { string = "Space Layout", font = font_bold, color = theme.BLUE },
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    ["label.padding_top"] = 4,
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
      icon = { string = layout.icon, color = theme.SAPPHIRE },
      label = { string = layout.name, font = font_small },
      ["icon.padding_left"] = 8,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      click_script = layout.cmd .. "; sketchybar --trigger space_mode_refresh; sketchybar --set control_center popup.drawing=off",
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
    label = { string = "Layout Ops", font = font_bold, color = theme.GREEN },
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
      click_script = op.cmd .. "; sketchybar --set control_center popup.drawing=off",
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
  local shortcuts_running = check_service("skhd")
  local shortcuts_on_label = "Yabai Shortcuts: On"
  local shortcuts_off_label = "Yabai Shortcuts: Off"
  local shortcuts_label = shortcuts_running and shortcuts_on_label or shortcuts_off_label
  local shortcuts_color = shortcuts_running and theme.GREEN or theme.RED
  local toggle_script = SCRIPTS_DIR .. "/toggle_yabai_shortcuts.sh"
  if not path_exists(toggle_script) then
    toggle_script = SCRIPTS_DIR .. "/toggle_shortcuts.sh"
  end
  local toggle_action = path_exists(toggle_script) and (shell_quote(toggle_script) .. " toggle")
    or ("bash " .. shell_quote(CONFIG_DIR .. "/bin/open_control_panel.sh"))
  local update_action = string.format(
    "if pgrep -x skhd >/dev/null 2>&1; then sketchybar --set $NAME label='%s' icon.color=%s; else sketchybar --set $NAME label='%s' icon.color=%s; fi",
    shortcuts_on_label,
    theme.GREEN,
    shortcuts_off_label,
    theme.RED
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
    click_script = toggle_action .. "; " .. update_action .. "; sketchybar --set control_center popup.drawing=off",
    background = { drawing = false },
  })

  -- Separator
  table.insert(items, {
    name = "cc.sep3",
    position = "popup.control_center",
    icon = { drawing = false },
    label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
    ["label.padding_left"] = 8,
    background = { drawing = false },
  })

  -- Services Section
  table.insert(items, {
    name = "cc.services_header",
    position = "popup.control_center",
    icon = { string = "", drawing = false },
    label = { string = "Services", font = font_bold, color = theme.YELLOW },
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  })

  local services = {
    { name = "Yabai", proc = "yabai", restart = "yabai --restart-service" },
    { name = "skhd", proc = "skhd", restart = "skhd --restart-service" },
    { name = "SketchyBar", proc = "sketchybar", restart = "sketchybar --reload" },
  }

  for _, svc in ipairs(services) do
    local running = check_service(svc.proc)
    local status_icon = running and "●" or "○"
    local status_color = running and theme.GREEN or theme.RED
    table.insert(items, {
      name = "cc.svc." .. svc.name:lower():gsub(" ", ""),
      position = "popup.control_center",
      icon = { string = status_icon, color = status_color },
      label = { string = svc.name, font = font_small },
      ["icon.padding_left"] = 10,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      click_script = svc.restart .. "; sketchybar --set control_center popup.drawing=off",
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

  -- Workspace Status
  local dirty = get_dirty_count()
  table.insert(items, {
    name = "cc.workspace",
    position = "popup.control_center",
    icon = { string = "", color = dirty > 0 and theme.YELLOW or theme.GREEN },
    label = { string = dirty > 0 and string.format("%d dirty repos", dirty) or "Workspace clean", font = font_small },
    ["icon.padding_left"] = 8,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 8,
    ["label.padding_bottom"] = 4,
    click_script = "open ~/src",
    background = { drawing = false },
  })

  return items
end

return control_center
