-- Shared UI builder helpers for popup anchors and menu-style popup rows.
--
-- This intentionally stays small: it centralizes the repeated popup toggle,
-- close-after-action, anchor subscription, and menu_style row defaults without
-- forcing every popup through a new renderer.

local menu_style = require("menu_style")

local ui = {}

local function shell_quote(value)
  value = tostring(value or "")
  if value:match("^[%w_@%%+=:,./%-]+$") then
    return value
  end
  return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

local function sketchybar_bin(opts)
  opts = opts or {}
  local ctx = opts.ctx or opts
  return ctx.SKETCHYBAR_BIN or ctx.sketchybar_bin or opts.sketchybar_bin or "sketchybar"
end

local function append(layout, entry)
  if type(layout) == "table" then
    table.insert(layout, entry)
  end
  return entry
end

local function merge(base, extra)
  for key, value in pairs(extra or {}) do
    base[key] = value
  end
  return base
end

local function copy_table(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = copy_table(item)
  end
  return result
end

local function merge_missing(base, defaults)
  for key, value in pairs(defaults or {}) do
    if base[key] == nil then
      base[key] = copy_table(value)
    elseif type(base[key]) == "table" and type(value) == "table" then
      merge_missing(base[key], value)
    end
  end
  return base
end

local function theme_color(ctx, key, fallback)
  local theme = ctx and ctx.theme or {}
  return theme[key] or theme[fallback or "WHITE"] or "0xffcdd6f4"
end

function ui.anchor_chip_style(ctx, opts)
  opts = opts or {}
  local height = opts.height or (ctx and ctx.widget_height) or 22
  local radius = opts.corner_radius or math.max((ctx and ctx.widget_corner_radius) or 6, 10)
  return {
    drawing = opts.drawing ~= false,
    color = opts.color or (ctx and ctx.anchor_idle_bg) or "0x18313a46",
    border_width = opts.border_width or (ctx and ctx.anchor_idle_border_width) or 0,
    border_color = opts.border_color or (ctx and ctx.anchor_idle_border_color) or "0x00000000",
    corner_radius = radius,
    height = height,
    padding_left = opts.padding_left or 5,
    padding_right = opts.padding_right or 5,
  }
end

function ui.anchor_hover_env(ctx, opts)
  opts = opts or {}
  local idle = ui.anchor_chip_style(ctx, opts)
  local hover_bg = opts.hover_bg or (ctx and ctx.anchor_hover_bg) or "0x28505a6a"
  local hover_border_color = opts.hover_border_color
    or (ctx and (ctx.anchor_hover_border_color or ctx.hover_border_color))
    or theme_color(ctx, "WHITE")
  local hover_border_width = opts.hover_border_width
    or (ctx and (ctx.anchor_hover_border_width or ctx.hover_border_width))
    or 1
  local env = {
    BARISTA_ANCHOR_IDLE_DRAWING = idle.drawing and "on" or "off",
    BARISTA_ANCHOR_IDLE_BG = tostring(idle.color),
    BARISTA_ANCHOR_IDLE_BORDER_WIDTH = tostring(idle.border_width or 0),
    BARISTA_ANCHOR_IDLE_BORDER_COLOR = tostring(idle.border_color or "0x00000000"),
    BARISTA_ANCHOR_HOVER_BG = tostring(hover_bg),
    BARISTA_ANCHOR_HOVER_BORDER_WIDTH = tostring(hover_border_width),
    BARISTA_ANCHOR_HOVER_BORDER_COLOR = tostring(hover_border_color),
  }
  if ctx and (ctx.SKETCHYBAR_BIN or ctx.sketchybar_bin) then
    env.BARISTA_SKETCHYBAR_BIN = tostring(ctx.SKETCHYBAR_BIN or ctx.sketchybar_bin)
  end
  if ctx and ctx.hover_animation_curve then
    env.BARISTA_HOVER_ANIMATION_CURVE = tostring(ctx.hover_animation_curve)
  end
  if ctx and ctx.hover_animation_duration then
    env.BARISTA_HOVER_ANIMATION_DURATION = tostring(ctx.hover_animation_duration)
  end
  return merge(env, opts.env)
end

function ui.anchor_script(script, ctx, opts)
  if type(script) ~= "string" or script == "" then
    return script
  end
  if ctx and type(ctx.env_prefix) == "function" then
    return ctx.env_prefix(ui.anchor_hover_env(ctx, opts)) .. script
  end
  return script
end

function ui.apply_anchor_chip(props, ctx, opts)
  props = props or {}
  local styled = copy_table(props)
  styled.background = merge_missing(styled.background or {}, ui.anchor_chip_style(ctx, opts))
  return styled
end

function ui.toggle(item_name, opts)
  local bin = shell_quote(sketchybar_bin(opts))
  if item_name and item_name ~= "" then
    return string.format("%s -m --set %s popup.drawing=toggle", bin, shell_quote(item_name))
  end
  return string.format([[USER="${USER:-$(id -un)}" %s -m --set "$NAME" popup.drawing=toggle]], bin)
end

function ui.toggle_then_refresh_async(item_name, refresh_cmd, opts)
  local toggle_cmd = ui.toggle(item_name, opts)
  if type(refresh_cmd) ~= "string" or refresh_cmd == "" then
    return toggle_cmd
  end
  return string.format("%s; (%s) >/dev/null 2>&1 &", toggle_cmd, refresh_cmd)
end

function ui.close_after(parent, command, opts)
  local bin = shell_quote(sketchybar_bin(opts))
  local target = parent and parent ~= "" and shell_quote(parent) or [["$NAME"]]
  local close_cmd = string.format("%s -m --set %s popup.drawing=off", bin, target)
  if type(command) ~= "string" or command == "" then
    return close_cmd
  end
  return string.format("%s; %s", command, close_cmd)
end

function ui.anchor(layout, spec)
  spec = spec or {}
  local ctx = spec.ctx or {}
  local name = assert(spec.name, "ui.anchor requires spec.name")
  local props = spec.props or spec.item or {}
  append(layout, { type = "item", name = name, props = props })

  local delay = spec.post_config_delay or ctx.POST_CONFIG_DELAY or 0
  local bin = shell_quote(sketchybar_bin(ctx))
  local events = spec.events
  if type(events) == "table" and #events > 0 then
    append(layout, {
      action = "exec",
      cmd = string.format(
        "sleep %.1f; %s --subscribe %s %s",
        delay,
        bin,
        shell_quote(name),
        table.concat(events, " ")
      ),
    })
  elseif type(events) == "string" and events ~= "" then
    append(layout, {
      action = "exec",
      cmd = string.format("sleep %.1f; %s --subscribe %s %s", delay, bin, shell_quote(name), events),
    })
  end

  if spec.popup ~= false and spec.subscribe_popup ~= false then
    append(layout, { action = "subscribe_popup_autoclose", name = name })
  end
  if spec.hover ~= false then
    append(layout, { action = "attach_hover", name = name })
  end

  local associated_display = spec.associated_display or spec.associated_displays
  local associated_space = spec.associated_space
  if associated_display or associated_space then
    append(layout, {
      action = "exec",
      cmd = string.format(
        "sleep %.1f; %s --set %s%s%s",
        delay,
        bin,
        shell_quote(name),
        associated_display and (" associated_display=" .. shell_quote(associated_display)) or "",
        associated_space and (" associated_space=" .. shell_quote(associated_space)) or ""
      ),
    })
  end

  return name
end

function ui.popup_style(ctx, overrides)
  local style_ctx = ctx or {}
  if type(style_ctx.appearance) ~= "table" then
    style_ctx = setmetatable({
      appearance = type(style_ctx.state) == "table" and style_ctx.state.appearance or {},
    }, { __index = style_ctx })
  end

  local style = menu_style.compute(style_ctx)
  local result = {
    raw = style,
    font_small = style.font_small,
    font_header = style.font_header,
    item_height = style.item_height,
    header_height = style.header_height,
    item_corner_radius = style.item_corner_radius,
    padding = style.padding or {},
    label_color = style.label_color or theme_color(ctx, "WHITE"),
    header_bg_color = theme_color(ctx, "BG_SEC_COLR", "WHITE"),
    separator_color = theme_color(ctx, "DARK_WHITE", "SUBTEXT1"),
  }
  return merge(result, overrides)
end

function ui.item(parent, name, props, opts)
  opts = opts or {}
  local style = opts.style or ui.popup_style(opts.ctx)
  local padding = style.padding or {}
  local item = {
    name = name,
    position = "popup." .. (parent or "$NAME"),
    background = {
      drawing = false,
      corner_radius = style.item_corner_radius or 6,
      height = style.item_height,
    },
    ["icon.padding_left"] = padding.icon_left or 6,
    ["icon.padding_right"] = padding.icon_right or 6,
    ["label.padding_left"] = padding.label_left or 8,
    ["label.padding_right"] = padding.label_right or 8,
  }
  return merge(item, props)
end

function ui.header(layout, parent, name, label, opts)
  opts = opts or {}
  local style = opts.style or ui.popup_style(opts.ctx)
  local item = ui.item(parent, name, {
    icon = opts.icon or { string = "", drawing = false },
    label = label,
    ["label.font"] = opts["label.font"] or opts.font or style.font_header,
    ["label.color"] = opts["label.color"] or opts.color or style.label_color,
    background = {
      drawing = opts.background_drawing ~= false,
      color = opts.background_color or style.header_bg_color,
      corner_radius = style.item_corner_radius,
      height = style.header_height,
    },
  }, { style = style })
  merge(item, opts.props)
  return append(layout, opts.layout_entry and { type = "item", name = name, props = item } or item)
end

function ui.separator(layout, parent, name, opts)
  opts = opts or {}
  local style = opts.style or ui.popup_style(opts.ctx)
  local item = ui.item(parent, name, {
    icon = opts.icon or { string = "", drawing = false },
    label = opts.label or "───────────────",
    ["label.font"] = opts["label.font"] or opts.font or style.font_small,
    ["label.color"] = opts["label.color"] or opts.color or style.separator_color,
    background = { drawing = false },
  }, { style = style })
  merge(item, opts.props)
  return append(layout, opts.layout_entry and { type = "item", name = name, props = item } or item)
end

function ui.row(layout, parent, name, spec)
  spec = spec or {}
  local style = spec.style or ui.popup_style(spec.ctx)
  local background = {
    drawing = false,
    corner_radius = style.item_corner_radius,
    height = style.item_height,
  }
  if spec.prominent then
    background = {
      drawing = true,
      color = spec.prominent_color or "0x20343a58",
      corner_radius = style.item_corner_radius,
      height = style.item_height,
    }
  end

  local hover = spec.hover
  if hover == nil then
    hover = spec.action ~= nil or spec.click_script ~= nil
  end

  local item = ui.item(parent, name, {
    icon = spec.icon or "",
    label = spec.label or "",
    ["label.font"] = spec["label.font"] or spec.font or style.font_small,
    ["label.color"] = spec["label.color"] or spec.label_color or style.label_color,
    click_script = spec.click_script or (spec.action and ui.close_after(parent, spec.action, spec)),
    background = spec.background or background,
    hover = hover == true,
  }, { style = style })
  merge(item, spec.props)
  return append(layout, spec.layout_entry and { type = "item", name = name, props = item, attach_hover = hover == true } or item)
end

function ui.section(layout, parent, prefix, section, opts)
  opts = opts or {}
  local style = opts.style or ui.popup_style(opts.ctx)
  if opts.separator then
    ui.separator(layout, parent, prefix .. ".sep", { style = style })
  end
  ui.header(layout, parent, prefix .. ".header", section.label or section.id or "Section", {
    style = style,
    color = section.color,
  })
  for _, entry in ipairs(section.entries or {}) do
    ui.row(layout, parent, prefix .. "." .. tostring(entry.id or entry.name), merge({
      style = style,
      icon = { string = entry.icon or "", color = entry.icon_color or section.color },
      label = entry.label,
      action = entry.action,
      prominent = entry.prominent == true,
      label_color = entry.label_color,
    }, opts.row_overrides or {}))
  end
  return layout
end

return ui
