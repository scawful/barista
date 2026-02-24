-- Bar appearance and defaults configuration.
-- Takes state, theme, state_module, and associated_displays; returns bar config, defaults, and helpers.

local function parse_color(value)
  if type(value) == "string" then
    local num = tonumber(value)
    if num then
      return num
    end
  end
  return value
end

local function clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function font_string(family, style, size)
  return string.format("%s:%s:%0.1f", family, style, size)
end

-- Compute bar dimensions, appearance, defaults, and helpers.
-- state_module: module with get_appearance(state, key, default)
function compute(state, theme, state_module, associated_displays)
  local bar_height = state_module.get_appearance(state, "bar_height", 28)
  local bar_corner_radius = state_module.get_appearance(state, "corner_radius", 0)
  local bar_color = parse_color(state_module.get_appearance(state, "bar_color", theme.bar.bg))
  local bar_blur_radius = tonumber(state_module.get_appearance(state, "blur_radius", 30))
  local bar_padding_left = tonumber(state_module.get_appearance(state, "bar_padding_left", 14)) or 14
  local bar_padding_right = tonumber(state_module.get_appearance(state, "bar_padding_right", 14)) or 14
  local bar_margin = tonumber(state_module.get_appearance(state, "bar_margin", 0)) or 0
  local bar_y_offset = tonumber(state_module.get_appearance(state, "bar_y_offset", 0)) or 0
  local bar_border_width = tonumber(state_module.get_appearance(state, "bar_border_width", 0)) or 0
  local bar_border_color = parse_color(state_module.get_appearance(state, "bar_border_color", "0x00000000"))
  local clock_font_style = state_module.get_appearance(state, "clock_font_style", "Semibold")
  local widget_scale = tonumber(state_module.get_appearance(state, "widget_scale", 1.0)) or 1.0
  widget_scale = clamp(widget_scale, 0.85, 1.25)

  local popup_padding = tonumber(state_module.get_appearance(state, "popup_padding", 8)) or 8
  local popup_corner_radius = tonumber(state_module.get_appearance(state, "popup_corner_radius", 6)) or 6
  local popup_border_width = tonumber(state_module.get_appearance(state, "popup_border_width", 2)) or 2
  local popup_border_color = parse_color(state_module.get_appearance(state, "popup_border_color", theme.WHITE))
  local popup_bg_color = parse_color(state_module.get_appearance(state, "popup_bg_color", theme.bar.bg))

  local hover_color = state_module.get_appearance(state, "hover_color", "0x40f5c2e7")
  local hover_border_color = state_module.get_appearance(state, "hover_border_color", "0x60cdd6f4")
  local hover_border_width = tonumber(state_module.get_appearance(state, "hover_border_width", 1)) or 1
  local hover_animation_curve = state_module.get_appearance(state, "hover_animation_curve", "sin")
  local hover_animation_duration = tonumber(state_module.get_appearance(state, "hover_animation_duration", 12)) or 12
  local submenu_hover_color = state_module.get_appearance(state, "submenu_hover_color", "0x80cba6f7")
  local submenu_idle_color = state_module.get_appearance(state, "submenu_idle_color", "0x00000000")
  local submenu_close_delay = tonumber(state_module.get_appearance(state, "submenu_close_delay", 0.25)) or 0.25

  local group_bg_color = parse_color(state_module.get_appearance(state, "group_bg_color", "0x30313244"))
  local group_border_color = parse_color(state_module.get_appearance(state, "group_border_color", "0x20585b70"))
  local group_border_width = tonumber(state_module.get_appearance(state, "group_border_width", 1)) or 1
  local group_corner_radius = tonumber(state_module.get_appearance(state, "group_corner_radius", 6)) or 6

  local widget_corner_radius = state.appearance and state.appearance.widget_corner_radius
  if type(widget_corner_radius) ~= "number" then
    if bar_corner_radius and bar_corner_radius > 0 then
      widget_corner_radius = math.max(bar_corner_radius - 1, 4)
    else
      widget_corner_radius = 6
    end
  end

  local function scaled(value)
    return math.floor(value * widget_scale + 0.5)
  end

  local icon_font_size = clamp(scaled(16), 12, 20)
  local label_font_size = clamp(scaled(14), 11, 18)
  local number_font_size = clamp(scaled(14), 11, 20)
  local small_font_size = clamp(scaled(13), 10, 16)
  local icon_padding = clamp(scaled(4), 3, 8)
  local label_padding = clamp(scaled(4), 3, 8)
  local item_padding = clamp(scaled(5), 4, 9)
  local base_widget_height = math.max(bar_height - 5, 18)
  local widget_height = clamp(
    math.floor(base_widget_height * widget_scale + 0.5),
    16,
    math.max(bar_height - 2, base_widget_height + 4)
  )

  local font_icon_family = state_module.get_appearance(state, "font_icon", "Hack Nerd Font")
  local font_text_family = state_module.get_appearance(state, "font_text", "Source Code Pro")
  local font_numbers_family = state_module.get_appearance(state, "font_numbers", "SF Mono")

  local settings = {
    font = {
      icon = font_icon_family,
      text = font_text_family,
      numbers = font_numbers_family,
      style_map = {
        Regular = "Regular",
        Medium = "Medium",
        Semibold = "Semibold",
        Bold = "Bold",
        Heavy = "Heavy"
      },
      sizes = {
        icon = icon_font_size,
        text = label_font_size,
        numbers = number_font_size,
        small = small_font_size,
      }
    },
    paddings = item_padding
  }

  local function popup_background()
    return {
      border_width = popup_border_width,
      corner_radius = popup_corner_radius,
      border_color = popup_border_color,
      color = popup_bg_color,
      padding_left = popup_padding,
      padding_right = popup_padding
    }
  end

  return {
    bar_height = bar_height,
    bar = {
      position = "top",
      height = bar_height,
      blur_radius = bar_blur_radius,
      color = bar_color,
      margin = bar_margin,
      padding_left = bar_padding_left,
      padding_right = bar_padding_right,
      corner_radius = bar_corner_radius,
      y_offset = bar_y_offset,
      border_width = bar_border_width,
      border_color = bar_border_color,
      display = "all",
    },
    defaults = {
      updates = "when_shown",
      padding_left = item_padding,
      padding_right = item_padding,
      ignore_association = true,
      associated_display = associated_displays,
      associated_space = "all",
      ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.icon),
      ["icon.color"] = theme.WHITE,
      ["icon.padding_left"] = icon_padding,
      ["icon.padding_right"] = icon_padding,
      ["label.font"] = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.text),
      ["label.color"] = theme.WHITE,
      ["label.padding_left"] = label_padding,
      ["label.padding_right"] = label_padding,
      background = {
        color = bar_color,
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
    },
    font_string = font_string,
    scaled = scaled,
    clamp = clamp,
    parse_color = parse_color,
    settings = settings,
    widget_height = widget_height,
    widget_corner_radius = widget_corner_radius,
    item_padding = item_padding,
    icon_padding = icon_padding,
    label_padding = label_padding,
    popup_background = popup_background,
    group_bg_color = group_bg_color,
    group_border_color = group_border_color,
    group_border_width = group_border_width,
    group_corner_radius = group_corner_radius,
    hover_color = hover_color,
    hover_border_color = hover_border_color,
    hover_border_width = hover_border_width,
    hover_animation_curve = hover_animation_curve,
    hover_animation_duration = hover_animation_duration,
    submenu_hover_color = submenu_hover_color,
    submenu_idle_color = submenu_idle_color,
    submenu_close_delay = submenu_close_delay,
  }
end

return { compute = compute }
