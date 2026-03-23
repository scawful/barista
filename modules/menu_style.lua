local menu_style = {}

local function clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function resolved_style(settings, style_name, fallback)
  local raw = tostring(style_name or fallback or "Regular")
  local normalized = raw:sub(1, 1):upper() .. raw:sub(2):lower()
  if settings.font.style_map[normalized] then
    return settings.font.style_map[normalized]
  end
  if settings.font.style_map[fallback] then
    return settings.font.style_map[fallback]
  end
  return settings.font.style_map["Regular"] or "Regular"
end

local function font_string(ctx, family, style, size)
  if type(ctx.font_string) == "function" then
    return ctx.font_string(family, style, size)
  end
  return string.format("%s:%s:%0.1f", family, style, size)
end

function menu_style.compute(ctx)
  local settings = ctx.settings
  local theme = ctx.theme
  local appearance = ctx.appearance or {}

  local popup_padding = tonumber(appearance.menu_padding) or tonumber(appearance.popup_padding) or 8
  local popup_border_width = tonumber(appearance.popup_border_width) or 2
  local popup_corner_radius = tonumber(appearance.popup_corner_radius) or 6
  local popup_border_color = appearance.popup_border_color or theme.WHITE
  local popup_bg_color = appearance.menu_popup_bg_color or appearance.popup_bg_color or theme.bar.bg
  local menu_label_color = appearance.menu_label_color or theme.WHITE

  local menu_font_size_offset = tonumber(appearance.menu_font_size_offset) or 1
  local menu_font_size = math.max((settings.font.sizes.small or 12) + menu_font_size_offset, 10)
  local menu_font_style = resolved_style(settings, appearance.menu_font_style or "Bold", "Semibold")
  local menu_header_style = resolved_style(settings, appearance.menu_header_font_style or "Bold", "Bold")
  local menu_font_small = font_string(ctx, settings.font.text, menu_font_style, menu_font_size)
  local menu_font_header = font_string(ctx, settings.font.text, menu_header_style, menu_font_size)

  local menu_item_height = tonumber(appearance.menu_item_height or appearance.popup_item_height or 0) or 0
  if menu_item_height <= 0 then
    menu_item_height = math.max(menu_font_size + 10, 20)
  end

  local menu_header_height = tonumber(appearance.menu_header_height or 0) or 0
  if menu_header_height <= 0 then
    menu_header_height = math.max(menu_item_height, menu_font_size + 12)
  end

  local menu_item_corner_radius = tonumber(appearance.menu_item_corner_radius or appearance.popup_item_corner_radius or 6) or 6
  local icon_left = tonumber(appearance.menu_icon_padding_left) or math.max(popup_padding - 2, 2)
  local icon_right = tonumber(appearance.menu_icon_padding_right) or popup_padding
  local label_left = tonumber(appearance.menu_label_padding_left) or popup_padding
  local label_right = tonumber(appearance.menu_label_padding_right) or popup_padding

  local submenu_hover_corner_radius = tonumber(appearance.submenu_hover_corner_radius or menu_item_corner_radius) or menu_item_corner_radius
  local submenu_hover_padding_left = tonumber(appearance.submenu_hover_padding_left) or clamp(popup_padding - 4, 2, 16)
  local submenu_hover_padding_right = tonumber(appearance.submenu_hover_padding_right) or clamp(popup_padding - 4, 2, 16)

  local function popup_background()
    return {
      border_width = popup_border_width,
      corner_radius = popup_corner_radius,
      border_color = popup_border_color,
      color = popup_bg_color,
      padding_left = popup_padding,
      padding_right = popup_padding,
    }
  end

  return {
    popup_padding = popup_padding,
    popup_border_width = popup_border_width,
    popup_corner_radius = popup_corner_radius,
    popup_border_color = popup_border_color,
    popup_bg_color = popup_bg_color,
    popup_background = popup_background,
    label_color = menu_label_color,
    font_small = menu_font_small,
    font_header = menu_font_header,
    item_height = menu_item_height,
    header_height = menu_header_height,
    item_corner_radius = menu_item_corner_radius,
    padding = {
      icon_left = icon_left,
      icon_right = icon_right,
      label_left = label_left,
      label_right = label_right,
    },
    submenu_hover_env = {
      SUBMENU_HOVER_CORNER_RADIUS = tostring(submenu_hover_corner_radius),
      SUBMENU_HOVER_PADDING_LEFT = tostring(submenu_hover_padding_left),
      SUBMENU_HOVER_PADDING_RIGHT = tostring(submenu_hover_padding_right),
    },
  }
end

return menu_style
