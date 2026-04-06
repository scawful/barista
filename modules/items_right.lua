-- Right-side bar items: clock, calendar, ai_resource, system_info, volume, battery, brackets.

local popup_items = require("popup_items")

local function get_layout(ctx)
  local factory = ctx.widget_factory
  local settings = ctx.settings
  local theme = ctx.theme
  local font_string = ctx.font_string
  local PLUGIN_DIR = ctx.PLUGIN_DIR
  local widget_height = ctx.widget_height
  local popup_background = ctx.popup_background
  local hover_script_cmd = ctx.hover_script_cmd
  local popup_toggle_action = ctx.popup_toggle_action
  local POST_CONFIG_DELAY = ctx.POST_CONFIG_DELAY
  local SKETCHYBAR_BIN = ctx.SKETCHYBAR_BIN
  local group_bg_color = ctx.group_bg_color
  local group_border_color = ctx.group_border_color
  local group_border_width = ctx.group_border_width
  local group_corner_radius = ctx.group_corner_radius
  local icon_for = ctx.icon_for
  local state_module = ctx.state_module
  local state = ctx.state
  local env_prefix = ctx.env_prefix
  local compiled_script = ctx.compiled_script
  local widget_daemon_enabled = ctx.widget_daemon_enabled == true
  local hover_color = ctx.hover_color
  local hover_animation_curve = ctx.hover_animation_curve
  local hover_animation_duration = ctx.hover_animation_duration
  local SCRIPTS_DIR = ctx.SCRIPTS_DIR or ""

  local layout = {}

  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end
  local media_control_script = SCRIPTS_DIR ~= "" and (SCRIPTS_DIR .. "/media_control.sh") or ""
  local function refresh_then_toggle(refresh_cmd, toggle_cmd)
    if refresh_cmd and refresh_cmd ~= "" then
      return refresh_cmd .. "; " .. toggle_cmd
    end
    return toggle_cmd
  end
  local function close_popup_after(item_name, command)
    if not command or command == "" then
      return string.format("sketchybar -m --set %s popup.drawing=off", item_name)
    end
    return string.format("%s; sketchybar -m --set %s popup.drawing=off", command, item_name)
  end
  local function build_script_action(path, ...)
    if not path or path == "" then
      return ""
    end
    if type(ctx.call_script) == "function" then
      return ctx.call_script(path, ...)
    end
    local parts = { path }
    for _, arg in ipairs({ ... }) do
      table.insert(parts, tostring(arg))
    end
    return table.concat(parts, " ")
  end

  -- Clock
  table.insert(layout, factory.create_clock({
    icon = icon_for("clock", "󰥔"),
    script = compiled_script("clock_widget", PLUGIN_DIR .. "/clock.sh"),
    update_freq = widget_daemon_enabled and false or 30,
    daemon_managed = widget_daemon_enabled,
    click_script = popup_toggle_action(),
    popup = {
      align = "right",
      background = popup_background()
    }
  }))
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "clock" })
  table.insert(layout, { action = "attach_hover", name = "clock" })

  -- Calendar popup items (tc = theme color with fallback for themes that omit accent keys)
  local calendar_items = {
    { name = "clock.calendar.header", icon = "", script = PLUGIN_DIR .. "/calendar.sh", update_freq = 1800, font_style = "Semibold", color = tc("LAVENDER"), ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small) },
    { name = "clock.calendar.weekdays", icon = "", font_style = "Bold", color = theme.DARK_WHITE or theme.WHITE },
  }
  for i = 1, 6 do
    table.insert(calendar_items, { name = string.format("clock.calendar.week%d", i), icon = "", font_style = "Regular", color = theme.WHITE })
  end
  table.insert(calendar_items, { name = "clock.calendar.summary", icon = "", font_style = "Semibold", color = tc("YELLOW") })
  table.insert(calendar_items, { name = "clock.calendar.weekend", icon = "", font_style = "Regular", color = tc("SKY") })
  table.insert(calendar_items, { name = "clock.calendar.progress", icon = "", font_style = "Regular", color = theme.DARK_WHITE or theme.WHITE })
  table.insert(calendar_items, { name = "clock.calendar.footer", icon = "", font_style = "Regular", color = theme.DARK_WHITE or theme.WHITE })

  for _, item in ipairs(calendar_items) do
    local is_header = item.name == "clock.calendar.header"
    local is_summary = item.name == "clock.calendar.summary"
    local is_footer = item.name == "clock.calendar.footer"
    local is_text_row = is_header or is_summary or is_footer or item.name == "clock.calendar.weekend" or item.name == "clock.calendar.progress"
    local item_font = settings.font.numbers
    if is_text_row then item_font = settings.font.text end
    local opts = {
      position = "popup.clock",
      icon = item.icon or "",
      label = "",
      ["label.font"] = font_string(item_font, settings.font.style_map[item.font_style or "Regular"] or settings.font.style_map["Regular"], is_header and settings.font.sizes.text or settings.font.sizes.small),
      ["label.color"] = item.color or theme.WHITE,
      ["icon.font"] = item["icon.font"] or font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small),
      ["icon.drawing"] = item.icon ~= "" and true or false,
      ["label.padding_left"] = 6,
      ["label.padding_right"] = 6,
      background = { drawing = false },
    }
    if item.script then opts.script = item.script end
    if item.update_freq then opts.update_freq = item.update_freq end
    table.insert(layout, { type = "item", name = item.name, props = opts })
  end


  -- System Info
  local system_info_fast_bin = compiled_script("system_info_widget", "")
  local system_info_env = env_prefix({
    BARISTA_ICON_CPU = state_module.get_icon(state, "cpu", ""),
    BARISTA_ICON_MEM = state_module.get_icon(state, "memory", ""),
    BARISTA_ICON_DISK = state_module.get_icon(state, "disk", ""),
    BARISTA_ICON_WIFI = state_module.get_icon(state, "wifi", ""),
    BARISTA_ICON_WIFI_OFF = state_module.get_icon(state, "wifi_off", ""),
    BARISTA_ICON_SWAP = state_module.get_icon(state, "swap", ""),
    BARISTA_ICON_UPTIME = state_module.get_icon(state, "uptime", ""),
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
    SYSTEM_INFO_BIN = system_info_fast_bin,
  })
  local system_info_script = system_info_env .. PLUGIN_DIR .. "/system_info.sh"
  table.insert(layout, factory.create_system_info({
    script = system_info_script,
    update_freq = widget_daemon_enabled and false or 45,
    daemon_managed = widget_daemon_enabled,
    click_script = refresh_then_toggle(system_info_script .. " popup_refresh", popup_toggle_action()),
  }))
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "system_info" })
  table.insert(layout, { action = "attach_hover", name = "system_info" })

  local info_flags = state.system_info_items or {}
  local function info_enabled(key)
    local v = info_flags[key]
    if v == nil then return true end
    return v
  end

  local system_info_items = {}
  if info_enabled("cpu") then table.insert(system_info_items, { name = "system_info.cpu", icon = "", label = "CPU …" }) end
  if info_enabled("mem") then table.insert(system_info_items, { name = "system_info.mem", icon = "", label = "Mem …" }) end
  if info_enabled("disk") then table.insert(system_info_items, { name = "system_info.disk", icon = "", label = "Disk …" }) end
  if info_enabled("net") then table.insert(system_info_items, { name = "system_info.net", icon = icon_for("wifi", "󰖩"), label = "Wi-Fi …" }) end
  if info_enabled("swap") then table.insert(system_info_items, { name = "system_info.swap", icon = "󰾴", label = "Swap …" }) end
  if info_enabled("uptime") then table.insert(system_info_items, { name = "system_info.uptime", icon = "󰥔", label = "Uptime …" }) end
  if info_enabled("procs") then table.insert(system_info_items, { name = "system_info.procs", icon = icon_for("cpu", "󰻠"), label = "Top CPU …", action = "open -a 'Activity Monitor'" }) end
  table.insert(system_info_items, { name = "system_info.activity", icon = "󰨇", label = "Activity Monitor", action = "open -a 'Activity Monitor'" })
  table.insert(system_info_items, { name = "system_info.settings", icon = "", label = "System Settings", action = "open -a 'System Settings'" })

  for _, item in ipairs(system_info_items) do
    local should_hover = item.hover == true
    local opts = {
      position = "popup.system_info",
      icon = item.icon,
      label = item.label,
    }
    if should_hover then
      opts.script = hover_script_cmd
    end
    if item.action then
      opts.click_script = close_popup_after("system_info", item.action)
    end
    table.insert(layout, { type = "item", name = item.name, props = opts, attach_hover = should_hover })
  end

  table.insert(layout, factory.create_bracket("right_group_1", { "clock", "system_info" }, {
    background = {
      color = group_bg_color,
      corner_radius = math.max(group_corner_radius, 4),
      height = math.max(widget_height + 2, 18),
      border_width = group_border_width,
      border_color = group_border_color,
    }
  }))

  -- Volume
  local volume_env = env_prefix({
    BARISTA_ICON_VOLUME = state_module.get_icon(state, "volume", ""),
    BARISTA_VOLUME_OK = tc("GREEN"),
    BARISTA_VOLUME_WARN = tc("YELLOW"),
    BARISTA_VOLUME_LOW = tc("RED"),
    BARISTA_VOLUME_MUTE = tc("BLUE"),
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
  })
  local volume_script = volume_env .. PLUGIN_DIR .. "/volume.sh"
  local volume_click_script = volume_env .. PLUGIN_DIR .. "/volume_click.sh"
  table.insert(layout, factory.create_volume({
    script = volume_script,
    click_script = volume_click_script,
    popup = { align = "right", background = popup_background() }
  }))
  table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --subscribe volume volume_change", POST_CONFIG_DELAY, SKETCHYBAR_BIN) })
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "volume" })
  table.insert(layout, { action = "attach_hover", name = "volume" })

  local add_vol = popup_items.make_add("volume", { hover_script = hover_script_cmd })
  table.insert(layout, add_vol("volume.header", {
    icon = "",
    label = "Audio",
    ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
    background = { drawing = false },
  }))
  table.insert(layout, add_vol("volume.state", {
    icon = "󰕾",
    label = "Volume …",
    ["label.font"] = font_small,
    background = { drawing = false },
  }))
  table.insert(layout, add_vol("volume.output", {
    icon = "󰓃",
    label = "Output …",
    ["label.font"] = font_small,
    background = { drawing = false },
  }))
  for i = 1, 4 do
    table.insert(layout, add_vol(string.format("volume.output.%d", i), {
      icon = "󰓃",
      label = string.format("Output %d", i),
      click_script = close_popup_after("volume", build_script_action(media_control_script, "set-output", tostring(i))),
      ["label.font"] = font_small,
      drawing = false,
      background = { drawing = false },
    }))
  end
  table.insert(layout, add_vol("volume.media", {
    icon = "󰎈",
    label = "Nothing Playing",
    ["label.font"] = font_small,
    background = { drawing = false },
  }))
  table.insert(layout, add_vol("volume.sep0", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_small,
    ["label.color"] = "0x40cdd6f4",
    background = { drawing = false },
  }))
  local volume_actions = {
    { name = "volume.transport.prev", icon = "󰒮", label = "Previous", action = build_script_action(media_control_script, "previous") },
    { name = "volume.transport.toggle", icon = "󰐊", label = "Play", action = build_script_action(media_control_script, "playpause") },
    { name = "volume.transport.next", icon = "󰒭", label = "Next", action = build_script_action(media_control_script, "next") },
    { name = "volume.mute", icon = "󰖁", label = "Toggle Mute", action = "osascript -e 'set volume output muted not (output muted of (get volume settings))'" },
    { name = "volume.settings", icon = "", label = "Sound Settings", action = "open -b com.apple.systempreferences /System/Library/PreferencePanes/Sound.prefPane" },
  }
  for _, entry in ipairs(volume_actions) do
    table.insert(layout, add_vol(entry.name, {
      icon = entry.icon,
      label = entry.label,
      click_script = close_popup_after("volume", entry.action),
      ["label.font"] = font_small,
    }))
  end

  -- Battery
  local battery_fast_bin = compiled_script("widget_manager", "")
  local battery_env = env_prefix({
    BARISTA_ICON_BATTERY = state_module.get_icon(state, "battery", ""),
    BARISTA_BATTERY_LABEL_MODE = "percent",
    BARISTA_BATTERY_FAST_BIN = battery_fast_bin,
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
  })
  local battery_script = battery_env .. PLUGIN_DIR .. "/battery.sh '" .. tc("GREEN") .. "' '" .. tc("YELLOW") .. "' '" .. tc("RED") .. "' '" .. tc("BLUE") .. "'"
  table.insert(layout, factory.create_battery({
    script = battery_script,
    update_freq = widget_daemon_enabled and false or 120,
    daemon_managed = widget_daemon_enabled,
    click_script = refresh_then_toggle(battery_script .. " popup_refresh", popup_toggle_action()),
    popup = { align = "right", background = popup_background() }
  }))
  table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --subscribe battery system_woke power_source_change", POST_CONFIG_DELAY, SKETCHYBAR_BIN) })
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "battery" })
  table.insert(layout, { action = "attach_hover", name = "battery" })

  local add_bat = popup_items.make_add("battery", { hover_script = hover_script_cmd })
  table.insert(layout, add_bat("battery.header", {
    icon = "",
    label = "Battery",
    ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
    background = { drawing = false },
  }))
  local battery_items = {
    { name = "battery.status", icon = "󰁹", label = "Status: …" },
    { name = "battery.time", icon = "󰥔", label = "Time: …" },
    { name = "battery.power", icon = "", label = "Power: …" },
    { name = "battery.cycle", icon = "󰑓", label = "Cycles: …" },
    { name = "battery.health", icon = "󰓽", label = "Health: …" },
    { name = "battery.settings", icon = "", label = "Battery Settings", action = "open -b com.apple.systempreferences /System/Library/PreferencePanes/Battery.prefPane" },
  }
  for _, entry in ipairs(battery_items) do
    table.insert(layout, add_bat(entry.name, {
      icon = entry.icon,
      label = entry.label,
      click_script = entry.action and close_popup_after("battery", entry.action) or nil,
      ["label.font"] = font_small,
    }))
  end

  table.insert(layout, factory.create_bracket("right_group_2", { "volume", "battery" }, {
    background = {
      color = group_bg_color,
      corner_radius = math.max(group_corner_radius, 4),
      height = math.max(widget_height + 2, 18),
      border_width = group_border_width,
      border_color = group_border_color,
    }
  }))

  table.insert(layout, { action = "exec", cmd = string.format("%s --trigger volume_change && %s --update battery", SKETCHYBAR_BIN, SKETCHYBAR_BIN) })

  return layout
end

return { get_layout = get_layout }
