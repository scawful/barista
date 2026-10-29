-- Bar appearance and defaults configuration.
-- Takes state, theme, state_module, and associated_displays; returns bar config, defaults, and helpers.

local display_profile = require("display_profile")

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

local function truthy(value, default_value)
  if value == nil then return default_value end
  if type(value) == "boolean" then return value end
  if type(value) == "number" then return value ~= 0 end
  if type(value) == "string" then
    local normalized = value:lower()
    if normalized == "0" or normalized == "false" or normalized == "off" or normalized == "no" or normalized == "disabled" then
      return false
    end
    if normalized == "1" or normalized == "true" or normalized == "on" or normalized == "yes" or normalized == "enabled" then
      return true
    end
  end
  return default_value
end

local function font_string(family, style, size)
  return string.format("%s:%s:%0.1f", family, style, size)
end

-- macOS ships SF as hidden system families; the public names only resolve
-- when the Apple font packages are installed, otherwise CoreText falls back
-- to Helvetica.
local FONT_FAMILY_ALIASES = {
  ["SF Pro"] = "System Font",
  ["SF Pro Text"] = "System Font",
  ["SF Pro Display"] = "System Font",
  ["SF Mono"] = ".SF NS Mono",
}

local function resolve_font_family(family)
  return FONT_FAMILY_ALIASES[family] or family
end

-- Compute bar dimensions, appearance, defaults, and helpers.
-- state_module: module with get_appearance(state, key, default)
function compute(state, theme, state_module, associated_displays, detected_display_profile)
  local bar_height = state_module.get_appearance(state, "bar_height", 28)
  local configured_bar_height = bar_height
  local bar_corner_radius = state_module.get_appearance(state, "corner_radius", 0)
  -- Which corners corner_radius rounds: all, top, bottom, none. Needs the
  -- Barista SketchyBar fork, so "all" (stock behavior) is never sent.
  local bar_corners = tostring(state_module.get_appearance(state, "bar_corners", "all")):lower()
  if bar_corners ~= "top" and bar_corners ~= "bottom" and bar_corners ~= "none" then
    bar_corners = nil
  end
  local bar_color = parse_color(state_module.get_appearance(state, "bar_color", theme.bar.bg))
  local bar_blur_radius = tonumber(state_module.get_appearance(state, "blur_radius", 30))
  local bar_padding_left = tonumber(state_module.get_appearance(state, "bar_padding_left", 14)) or 14
  local bar_padding_right = tonumber(state_module.get_appearance(state, "bar_padding_right", 14)) or 14
  local bar_margin = tonumber(state_module.get_appearance(state, "bar_margin", 0)) or 0
  local bar_y_offset = tonumber(state_module.get_appearance(state, "bar_y_offset", 0)) or 0
  local bar_border_width = tonumber(state_module.get_appearance(state, "bar_border_width", 0)) or 0
  local bar_border_color = parse_color(state_module.get_appearance(state, "bar_border_color", "0x00000000"))
  local clock_font_style = state_module.get_appearance(state, "clock_font_style", "Semibold")
  local widget_scale_base = tonumber(state_module.get_appearance(state, "widget_scale", 1.0)) or 1.0
  local auto_more_space_scaling = truthy(state_module.get_appearance(state, "auto_more_space_scaling", true), true)
  local auto_display_density = truthy(state_module.get_appearance(state, "auto_display_density", true), true)
  local more_space_widget_scale_boost = tonumber(state_module.get_appearance(state, "more_space_widget_scale_boost", 0.08)) or 0.08
  more_space_widget_scale_boost = clamp(more_space_widget_scale_boost, 0, 0.20)

  local display_scaling = detected_display_profile
  if display_scaling == nil and (auto_more_space_scaling or auto_display_density) then
    display_scaling = display_profile.detect()
  end

  local effective_more_space_boost = 0
  if auto_more_space_scaling and display_scaling and display_scaling.more_space_active then
    effective_more_space_boost = more_space_widget_scale_boost
    local top_inset = tonumber(display_scaling.top_inset) or 0
    if top_inset > bar_height then
      bar_height = top_inset
    end
  end

  local density = "comfortable"
  local density_scale_adjust = 0
  local hide_anchor_labels = false
  local optional_wide_only = false
  local narrow_status_strip = false
  local split_layout = false
  local clock_style = "full"
  local wide_displays = ""
  local narrow_displays = ""
  local density_fingerprint = ""
  if auto_display_density and display_scaling then
    density = display_scaling.density or "comfortable"
    hide_anchor_labels = display_scaling.hide_anchor_labels == true
    optional_wide_only = display_scaling.optional_wide_only == true
    narrow_status_strip = display_scaling.narrow_status_strip == true
    split_layout = display_scaling.split_layout == true
    clock_style = display_scaling.clock_style or "full"
    wide_displays = display_scaling.wide_displays or ""
    narrow_displays = display_scaling.narrow_displays or ""
    density_fingerprint = display_scaling.fingerprint or ""
    -- Only shrink the shared bar chrome when every display is narrow.
    -- Mixed wide+narrow setups keep the wide desktop at full scale.
    if not split_layout then
      if density == "dense" then
        density_scale_adjust = -0.12
        bar_padding_left = math.min(bar_padding_left, 6)
        bar_padding_right = math.min(bar_padding_right, 6)
      elseif density == "compact" then
        density_scale_adjust = -0.06
        bar_padding_left = math.min(bar_padding_left, 10)
        bar_padding_right = math.min(bar_padding_right, 10)
      end
    end
  end

  local widget_scale = clamp(widget_scale_base + effective_more_space_boost + density_scale_adjust, 0.75, 1.25)

  local popup_padding = tonumber(state_module.get_appearance(state, "popup_padding", 8)) or 8
  local popup_corner_radius = tonumber(state_module.get_appearance(state, "popup_corner_radius", 10)) or 10
  local popup_border_width = tonumber(state_module.get_appearance(state, "popup_border_width", 1)) or 1
  local popup_border_color = parse_color(state_module.get_appearance(state, "popup_border_color", theme.WHITE))
  local popup_blur_radius = tonumber(state_module.get_appearance(state, "popup_blur_radius", 20)) or 20
  local popup_shadow = truthy(state_module.get_appearance(state, "popup_shadow", true), true)
  -- Popup bg defaults to bar color at 0xE0 alpha so the popup blur shows through
  local raw_popup_bg = state_module.get_appearance(state, "popup_bg_color", nil)
  local popup_bg_color
  if raw_popup_bg then
    popup_bg_color = parse_color(raw_popup_bg)
  else
    local base = parse_color(theme.bar.bg) or 0xC021162F
    if type(base) == "number" then
      popup_bg_color = bit32 and bit32.bor(bit32.band(base, 0x00FFFFFF), 0xE0000000)
        or (base % 0x1000000) + 0xE0000000
    else
      popup_bg_color = base
    end
  end

  local hover_color = state_module.get_appearance(state, "hover_color", "0x40f5c2e7")
  local hover_border_color = state_module.get_appearance(state, "hover_border_color", "0x60cdd6f4")
  local hover_border_width = tonumber(state_module.get_appearance(state, "hover_border_width", 1)) or 1
  local hover_animation_curve = state_module.get_appearance(state, "hover_animation_curve", "sin")
  local hover_animation_duration = tonumber(state_module.get_appearance(state, "hover_animation_duration", 8)) or 8
  -- SketchyBar expects whole frame counts; zero selects an immediate update.
  if hover_animation_duration ~= hover_animation_duration or math.abs(hover_animation_duration) == math.huge then
    hover_animation_duration = 8
  end
  hover_animation_duration = math.max(0, math.floor(hover_animation_duration))
  local fast_hover_duration = math.min(hover_animation_duration, 3)
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

  local font_icon_family = resolve_font_family(state_module.get_appearance(state, "font_icon", "Hack Nerd Font"))
  local font_text_family = resolve_font_family(state_module.get_appearance(state, "font_text", "Source Code Pro"))
  local font_numbers_family = resolve_font_family(state_module.get_appearance(state, "font_numbers", "SF Mono"))
  local font_popup_family = resolve_font_family(state_module.get_appearance(state, "font_popup", "SF Pro"))

  local settings = {
    font = {
      icon = font_icon_family,
      text = font_text_family,
      numbers = font_numbers_family,
      popup = font_popup_family,
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

  local popup_icon_width = tonumber(state_module.get_appearance(state, "popup_icon_width", 26)) or 26

  local function swap_font_family(font, from_family, to_family)
    if type(font) == "string" then
      local family, rest = font:match("^(.-)(:.*)$")
      if family == from_family then return to_family .. rest end
    elseif type(font) == "table" and font.family == from_family then
      local copy = {}
      for key, value in pairs(font) do copy[key] = value end
      copy.family = to_family
      return copy
    end
    return font
  end

  local function single_glyph_icon(props)
    if props["icon.drawing"] == false then return false end
    local icon = props["icon.string"] or props.icon
    if type(icon) == "table" then
      if icon.drawing == false or icon.width ~= nil then return false end
      icon = icon.string
    end
    if type(icon) ~= "string" or icon == "" then return false end
    local _, glyphs = icon:gsub("[^\128-\191]", "")
    return glyphs == 1
  end

  -- Popup rows use the proportional popup font for text labels (numeric rows
  -- keep the numbers font) and a fixed, centered icon column so labels align.
  local function style_popup_row(props)
    if type(props) ~= "table" or type(props.position) ~= "string"
      or not props.position:match("^popup%.") then
      return props
    end
    local from_family, to_family = settings.font.text, settings.font.popup
    local label_table = type(props.label) == "table" and props.label or nil
    if props["label.font"] == nil and not (label_table and label_table.font) then
      props["label.font"] = font_string(to_family, settings.font.style_map["Regular"], settings.font.sizes.small)
    end
    if props["label.font"] then
      props["label.font"] = swap_font_family(props["label.font"], from_family, to_family)
    end
    if label_table and label_table.font then
      label_table.font = swap_font_family(label_table.font, from_family, to_family)
    end
    if props["icon.width"] == nil and single_glyph_icon(props) then
      props["icon.width"] = popup_icon_width
      props["icon.align"] = "center"
    end
    return props
  end

  return {
    bar_height = bar_height,
    configured_bar_height = configured_bar_height,
    bar = {
      position = "top",
      topmost = "off",
      height = bar_height,
      blur_radius = bar_blur_radius,
      color = bar_color,
      margin = bar_margin,
      padding_left = bar_padding_left,
      padding_right = bar_padding_right,
      corner_radius = bar_corner_radius,
      corners = bar_corners,
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
      ["popup.blur_radius"] = popup_blur_radius,
      ["popup.background.shadow.drawing"] = popup_shadow,
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
    widget_scale = widget_scale,
    widget_scale_base = widget_scale_base,
    more_space_widget_scale_boost = effective_more_space_boost,
    display_profile = display_scaling,
    display_density = density,
    density_fingerprint = density_fingerprint,
    hide_anchor_labels = hide_anchor_labels,
    optional_wide_only = optional_wide_only,
    narrow_status_strip = narrow_status_strip,
    split_layout = split_layout,
    clock_style = clock_style,
    wide_displays = wide_displays,
    narrow_displays = narrow_displays,
    widget_corner_radius = widget_corner_radius,
    item_padding = item_padding,
    icon_padding = icon_padding,
    label_padding = label_padding,
    popup_background = popup_background,
    style_popup_row = style_popup_row,
    group_bg_color = group_bg_color,
    group_border_color = group_border_color,
    group_border_width = group_border_width,
    group_corner_radius = group_corner_radius,
    hover_color = hover_color,
    hover_border_color = hover_border_color,
    hover_border_width = hover_border_width,
    hover_animation_curve = hover_animation_curve,
    hover_animation_duration = hover_animation_duration,
    fast_hover_duration = fast_hover_duration,
    submenu_hover_color = submenu_hover_color,
    submenu_idle_color = submenu_idle_color,
    submenu_close_delay = submenu_close_delay,
  }
end

return { compute = compute }
