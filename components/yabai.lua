-- components/yabai.lua

local M = {}

function M.setup(config)
  local sbar = config.sbar
  local theme = config.theme
  local settings = config.font
  local state_module = config.state_module
  local widget_factory = config.widget_factory
  local subscribe_popup_autoclose = config.subscribe_popup_autoclose
  local attach_hover = config.attach_hover
  local font_string = config.font_string
  local call_script = config.call_script
  local HOVER_SCRIPT = config.HOVER_SCRIPT
  local YABAI_CONTROL_SCRIPT = config.YABAI_CONTROL_SCRIPT
  local CONFIG_DIR = config.paths.config

  -- Check if yabai is available before setting up the widget
  if not config.yabai_available() then
    return
  end

  widget_factory.create("yabai_status", {
    position = "left",
    icon = "󱂬",
    label = "yabai…",
    update_freq = 60,
    script = config.paths.plugins .. "/yabai_status.sh",
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    background_color = state_module.get_widget_color(config.state, "yabai_status", theme.BG_SEC_COLR),
    popup = {
      align = "left",
      background = {
        border_width = 2,
        corner_radius = 6,
        border_color = theme.WHITE,
        color = theme.bar.bg,
        padding_left = 8,
        padding_right = 8,
        padding_top = 6,
        padding_bottom = 8
      }
    }
  })
  subscribe_popup_autoclose("yabai_status")
  attach_hover("yabai_status")
  sbar.exec("sketchybar --add event yabai_status_refresh")
  sbar.exec("sketchybar --subscribe yabai_status yabai_status_refresh system_woke front_app_switched space_change")
  sbar.exec("sketchybar --trigger yabai_status_refresh")

  local function add_yabai_popup_item(id, props)
    local defaults = {
      position = "popup.yabai_status",
      script = HOVER_SCRIPT,
      ["icon.padding_left"] = 6,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    }
    for k, v in pairs(props) do
      defaults[k] = v
    end
    sbar.add("item", id, defaults)
  end

  local font_small = font_string(settings.text, settings.style_map["Semibold"], settings.sizes.small)

  add_yabai_popup_item("yabai.status.header", {
    icon = "",
    label = "Space Layout Modes",
    ["label.font"] = font_string(settings.text, settings.style_map["Bold"], settings.sizes.small),
    background = { drawing = false },
  })

  local mode_actions = {
    { name = "yabai.status.float", icon = "󰒄", label = "Float (default)", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "float") },
    { name = "yabai.status.bsp", icon = "󰆾", label = "BSP Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "bsp") },
    { name = "yabai.status.stack", icon = "󰓩", label = "Stack Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "stack") },
  }
  for _, entry in ipairs(mode_actions) do
    add_yabai_popup_item(entry.name, {
      icon = entry.icon,
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end

  add_yabai_popup_item("yabai.status.sep1", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_string(settings.text, settings.style_map["Regular"], settings.sizes.small),
    ["label.color"] = theme.DARK_WHITE,
    background = { drawing = false },
  })

  add_yabai_popup_item("yabai.status.window.header", {
    icon = "",
    label = "Window Management",
    ["label.font"] = font_string(settings.text, settings.style_map["Bold"], settings.sizes.small),
    background = { drawing = false },
  })

  local window_actions = {
    { name = "yabai.status.balance", icon = "󰓅", label = "Balance Windows", action = call_script(YABAI_CONTROL_SCRIPT, "balance"), shortcut = "🌐B" },
    { name = "yabai.status.rotate", icon = "󰑞", label = "Rotate Layout", action = call_script(YABAI_CONTROL_SCRIPT, "space-rotate") },
    { name = "yabai.status.toggle", icon = "󱂬", label = "Toggle BSP/Stack", action = call_script(YABAI_CONTROL_SCRIPT, "toggle-layout") },
    { name = "yabai.status.flip_x", icon = "󰯌", label = "Flip Horizontal", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-x") },
    { name = "yabai.status.flip_y", icon = "󰯎", label = "Flip Vertical", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-y") },
  }
  for _, entry in ipairs(window_actions) do
    add_yabai_popup_item(entry.name, {
      icon = entry.icon,
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end

  add_yabai_popup_item("yabai.status.sep2", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_string(settings.text, settings.style_map["Regular"], settings.sizes.small),
    ["label.color"] = theme.DARK_WHITE,
    background = { drawing = false },
  })

  add_yabai_popup_item("yabai.status.nav.header", {
    icon = "",
    label = "Space Navigation",
    ["label.font"] = font_string(settings.text, settings.style_map["Bold"], settings.sizes.small),
    background = { drawing = false },
  })

  local nav_actions = {
    { name = "yabai.status.space.prev", icon = "󰆽", label = "Previous Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-prev"), shortcut = "🌐←" },
    { name = "yabai.status.space.next", icon = "󰆼", label = "Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-next"), shortcut = "🌐→" },
    { name = "yabai.status.space.recent", icon = "󰔰", label = "Recent Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-recent") },
    { name = "yabai.status.space.first", icon = "󰆿", label = "First Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-first") },
    { name = "yabai.status.space.last", icon = "󰆾", label = "Last Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-last") },
  }
  for _, entry in ipairs(nav_actions) do
    add_yabai_popup_item(entry.name, {
      icon = entry.icon,
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end
end

return M
