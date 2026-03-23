-- Widget Factory Module
-- Centralized widget creation and management

local widgets = {}

-- Widget factory for creating common widgets
function widgets.create_factory(sbar, theme, settings, state_data, metrics)
  local factory = {}
  local appearance = state_data.appearance or {}
  local widget_metrics = metrics or {}
  local widget_height = widget_metrics.widget_height or math.max((appearance.bar_height or 28) - 5, 18)
  local widget_corner_radius = widget_metrics.widget_corner_radius
  if widget_corner_radius == nil then
    local corner_radius = appearance.corner_radius or 0
    widget_corner_radius = corner_radius > 0 and math.max(corner_radius - 1, 4) or 6
  end
  local item_padding = widget_metrics.item_padding or 5
  local clock_font_style = appearance.clock_font_style or "Semibold"

  local function popup_background()
    local padding = appearance.popup_padding or 8
    return {
      border_width = appearance.popup_border_width or 2,
      corner_radius = appearance.popup_corner_radius or 6,
      border_color = appearance.popup_border_color or theme.WHITE,
      color = appearance.popup_bg_color or theme.bar.bg,
      padding_left = padding,
      padding_right = padding,
    }
  end

  -- Get widget color from state
  local function widget_color(name, fallback)
    local color = state_data.widget_colors and state_data.widget_colors[name]
    if type(color) == "string" then
      local num = tonumber(color)
      if num then return num end
    end
    return color or fallback
  end

  -- Primitive: create a raw item definition
  function factory.create_item(name, props)
    return { type = "item", name = name, props = props }
  end

  -- Primitive: create a raw bracket definition
  function factory.create_bracket(name, children, props)
    return { type = "bracket", name = name, children = children, props = props }
  end

  -- Create a standard widget with common properties
  function factory.create(name, config)
    local defaults = {
      position = config.position or "right",
      icon = config.icon or "",
      label = config.label or "",
      update_freq = config.update_freq,
      script = config.script,
      click_script = config.click_script,
      drawing = config.drawing,
      padding_left = item_padding,
      padding_right = item_padding,
      background = {
        color = widget_color(name, config.background_color or theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
    }

    -- Merge with custom config
    for key, value in pairs(config) do
      if key ~= "background_color" then
        defaults[key] = value
      end
    end

    sbar.add("item", name, defaults)
    return name
  end

  -- Create a popup widget
  function factory.create_popup(parent_name, config)
    local background = popup_background()
    local popup_config = {
      background = {
        border_width = background.border_width,
        corner_radius = background.corner_radius,
        border_color = background.border_color,
        color = background.color,
        padding_left = background.padding_left,
        padding_right = background.padding_right,
      }
    }

    -- Merge custom popup config
    if config then
      for key, value in pairs(config) do
        popup_config[key] = value
      end
    end

    sbar.set(parent_name, { popup = popup_config })
    return parent_name
  end

  -- Create a clock widget
  function factory.create_clock(config)
    local defaults = {
      position = "right",
      icon = "",
      update_freq = 10,
      drawing = state_data.widgets.clock ~= false,
      background = {
        color = widget_color("clock", theme.clock or theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
      ["label.font"] = string.format(
        "%s:%s:%0.1f",
        settings.font.numbers,
        settings.font.style_map[clock_font_style] or "Semibold",
        settings.font.sizes.numbers
      ),
    }

    for key, value in pairs(config or {}) do
      defaults[key] = value
    end

    sbar.add("item", "clock", defaults)
    return "clock"
  end

  -- Create a battery widget
  function factory.create_battery(config)
    local defaults = {
      position = "right",
      drawing = state_data.widgets.battery ~= false,
      update_freq = 120,
      background = {
        color = widget_color("battery", theme.battery or theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
    }

    for key, value in pairs(config or {}) do
      defaults[key] = value
    end

    sbar.add("item", "battery", defaults)
    return "battery"
  end

  -- Create a volume widget
  function factory.create_volume(config)
    local defaults = {
      position = "right",
      drawing = state_data.widgets.volume ~= false,
      background = {
        color = widget_color("volume", theme.volume or theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
    }

    for key, value in pairs(config or {}) do
      defaults[key] = value
    end

    sbar.add("item", "volume", defaults)
    return "volume"
  end

  -- Create a system info widget with popup
  function factory.create_system_info(config)
    local defaults = {
      position = "right",
      icon = "󰍛",
      label = "…",
      update_freq = 20,
      drawing = state_data.widgets.system_info ~= false,
      background = {
        color = widget_color("system_info", theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
      click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
      popup = {
        background = popup_background()
      }
    }

    for key, value in pairs(config or {}) do
      defaults[key] = value
    end

    sbar.add("item", "system_info", defaults)
    return "system_info"
  end

  -- Create network widget
  function factory.create_network(config)
    local defaults = {
      position = "right",
      icon = "󰓅",
      label = "NET …",
      drawing = state_data.widgets.network ~= false,
      update_freq = 15,
      background = {
        color = widget_color("network", theme.BG_SEC_COLR),
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
    }

    for key, value in pairs(config or {}) do
      defaults[key] = value
    end

    sbar.add("item", "network", defaults)
    return "network"
  end

  -- Update widget at runtime (without reload)
  function factory.update_runtime(widget_name, properties)
    local cmd_parts = {"sketchybar", "--set", widget_name}

    for key, value in pairs(properties) do
      table.insert(cmd_parts, key .. "=" .. tostring(value))
    end

    local cmd = table.concat(cmd_parts, " ")
    os.execute(cmd)
  end

  -- Update widget color at runtime
  function factory.update_color(widget_name, color)
    factory.update_runtime(widget_name, {
      ["background.color"] = color
    })
  end

  -- Toggle widget visibility at runtime
  function factory.toggle_drawing(widget_name, enabled)
    factory.update_runtime(widget_name, {
      drawing = enabled and "on" or "off"
    })
  end

  return factory
end

return widgets
