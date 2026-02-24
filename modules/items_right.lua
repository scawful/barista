-- Right-side bar items: clock, calendar, ai_resource, system_info, volume, battery, brackets.

local function register(ctx)
  local sbar = ctx.sbar
  local theme = ctx.theme
  local settings = ctx.settings
  local font_string = ctx.font_string
  local PLUGIN_DIR = ctx.PLUGIN_DIR
  local widget_height = ctx.widget_height
  local popup_background = ctx.popup_background
  local hover_script_cmd = ctx.hover_script_cmd
  local popup_toggle_action = ctx.popup_toggle_action
  local attach_hover = ctx.attach_hover
  local subscribe_popup_autoclose = ctx.subscribe_popup_autoclose
  local shell_exec = ctx.shell_exec
  local SKETCHYBAR_BIN = ctx.SKETCHYBAR_BIN
  local POST_CONFIG_DELAY = ctx.POST_CONFIG_DELAY
  local group_bg_color = ctx.group_bg_color
  local group_border_color = ctx.group_border_color
  local group_border_width = ctx.group_border_width
  local group_corner_radius = ctx.group_corner_radius
  local widget_factory = ctx.widget_factory
  local icon_for = ctx.icon_for
  local state_module = ctx.state_module
  local state = ctx.state
  local env_prefix = ctx.env_prefix
  local compiled_script = ctx.compiled_script
  local hover_color = ctx.hover_color
  local hover_animation_curve = ctx.hover_animation_curve
  local hover_animation_duration = ctx.hover_animation_duration
  local open_path = ctx.open_path
  local CODE_DIR = ctx.CODE_DIR

  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)

  -- Clock
  widget_factory.create_clock({
    icon = icon_for("clock", "󰥔"),
    script = compiled_script("clock_widget", PLUGIN_DIR .. "/clock.sh"),
    update_freq = 30,
    click_script = popup_toggle_action(),
    popup = {
      align = "right",
      background = popup_background()
    }
  })
  subscribe_popup_autoclose("clock")
  attach_hover("clock")

  -- Calendar popup items
  local calendar_items = {
    { name = "clock.calendar.header", icon = "", script = PLUGIN_DIR .. "/calendar.sh", update_freq = 1800, font_style = "Semibold", color = theme.LAVENDER, ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small) },
    { name = "clock.calendar.weekdays", icon = "", font_style = "Bold", color = theme.DARK_WHITE },
  }
  for i = 1, 6 do
    table.insert(calendar_items, { name = string.format("clock.calendar.week%d", i), icon = "", font_style = "Regular", color = theme.WHITE })
  end
  table.insert(calendar_items, { name = "clock.calendar.summary", icon = "", font_style = "Semibold", color = theme.YELLOW })
  table.insert(calendar_items, { name = "clock.calendar.weekend", icon = "", font_style = "Regular", color = theme.SKY })
  table.insert(calendar_items, { name = "clock.calendar.progress", icon = "", font_style = "Regular", color = theme.DARK_WHITE })
  table.insert(calendar_items, { name = "clock.calendar.footer", icon = "", font_style = "Regular", color = theme.DARK_WHITE })

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
    sbar.add("item", item.name, opts)
  end

  -- AI Resource
  sbar.add("item", "ai_resource", {
    position = "right",
    icon = { string = "󰾆", color = theme.GREEN },
    label = { string = "AI: NORM" },
    update_freq = 60,
    script = PLUGIN_DIR .. "/ai_resource_toggle.sh",
    click_script = PLUGIN_DIR .. "/ai_resource_toggle.sh",
  })
  shell_exec(string.format("sleep %.1f; %s --subscribe ai_resource ai_resource_update", POST_CONFIG_DELAY, SKETCHYBAR_BIN))

  -- System Info
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
  })
  local system_info_script = system_info_env .. PLUGIN_DIR .. "/system_info.sh"
  widget_factory.create_system_info({
    script = system_info_script,
    update_freq = 45,
    click_script = popup_toggle_action(),
  })
  subscribe_popup_autoclose("system_info")
  attach_hover("system_info")

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
    local opts = {
      position = "popup.system_info",
      icon = item.icon,
      label = item.label,
      script = hover_script_cmd,
    }
    if item.action then
      opts.click_script = item.action .. "; sketchybar -m --set system_info popup.drawing=off"
    end
    sbar.add("item", item.name, opts)
    attach_hover(item.name)
  end

  sbar.add("bracket", { "clock", "system_info" }, {
    background = {
      color = group_bg_color,
      corner_radius = math.max(group_corner_radius, 4),
      height = math.max(widget_height + 2, 18),
      border_width = group_border_width,
      border_color = group_border_color,
    }
  })

  -- Volume
  local volume_env = env_prefix({
    BARISTA_ICON_VOLUME = state_module.get_icon(state, "volume", ""),
    BARISTA_VOLUME_OK = theme.GREEN,
    BARISTA_VOLUME_WARN = theme.YELLOW,
    BARISTA_VOLUME_LOW = theme.RED,
    BARISTA_VOLUME_MUTE = theme.BLUE,
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
  })
  local volume_script = volume_env .. PLUGIN_DIR .. "/volume.sh"
  widget_factory.create_volume({
    script = volume_script,
    click_script = PLUGIN_DIR .. "/volume_click.sh",
    popup = { align = "right", background = popup_background() }
  })
  shell_exec(string.format("sleep %.1f; %s --subscribe volume volume_change", POST_CONFIG_DELAY, SKETCHYBAR_BIN))
  subscribe_popup_autoclose("volume")
  attach_hover("volume")

  local popup_items = require("popup_items")
  local add_vol = popup_items.make_add(sbar, "volume", { hover_script = hover_script_cmd, attach_hover = attach_hover })
  add_vol("volume.header", {
    icon = "",
    label = "Volume Controls",
    ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
    background = { drawing = false },
  })
  local volume_actions = {
    { name = "volume.mute", icon = "󰖁", label = "Toggle Mute", action = "osascript -e 'set volume output muted not (output muted of (get volume settings))'" },
    { name = "volume.0", icon = "󰕿", label = "0%", action = "osascript -e 'set volume output volume 0'" },
    { name = "volume.10", icon = "󰕿", label = "10%", action = "osascript -e 'set volume output volume 10'" },
    { name = "volume.30", icon = "󰖀", label = "30%", action = "osascript -e 'set volume output volume 30'" },
    { name = "volume.50", icon = "󰖀", label = "50%", action = "osascript -e 'set volume output volume 50'" },
    { name = "volume.80", icon = "󰕾", label = "80%", action = "osascript -e 'set volume output volume 80'" },
    { name = "volume.100", icon = "󰕾", label = "100%", action = "osascript -e 'set volume output volume 100'" },
    { name = "volume.settings", icon = "", label = "Sound Settings", action = "open -b com.apple.systempreferences /System/Library/PreferencePanes/Sound.prefPane" },
  }
  for _, entry in ipairs(volume_actions) do
    add_vol(entry.name, { icon = entry.icon, label = entry.label, click_script = entry.action, ["label.font"] = font_small })
  end

  -- Battery
  local battery_env = env_prefix({
    BARISTA_ICON_BATTERY = state_module.get_icon(state, "battery", ""),
    BARISTA_BATTERY_LABEL_MODE = "percent",
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
  })
  widget_factory.create_battery({
    script = battery_env .. PLUGIN_DIR .. "/battery.sh '" .. theme.GREEN .. "' '" .. theme.YELLOW .. "' '" .. theme.RED .. "' '" .. theme.BLUE .. "'",
    update_freq = 120,
    click_script = popup_toggle_action(),
    popup = { align = "right", background = popup_background() }
  })
  shell_exec(string.format("sleep %.1f; %s --subscribe battery system_woke power_source_change", POST_CONFIG_DELAY, SKETCHYBAR_BIN))
  subscribe_popup_autoclose("battery")
  attach_hover("battery")

  local add_bat = popup_items.make_add(sbar, "battery", { hover_script = hover_script_cmd, attach_hover = attach_hover })
  add_bat("battery.header", {
    icon = "",
    label = "Battery",
    ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
    background = { drawing = false },
  })
  local battery_items = {
    { name = "battery.status", icon = "󰁹", label = "Status: …" },
    { name = "battery.time", icon = "󰥔", label = "Time: …" },
    { name = "battery.power", icon = "", label = "Power: …" },
    { name = "battery.cycle", icon = "󰑓", label = "Cycles: …" },
    { name = "battery.health", icon = "󰓽", label = "Health: …" },
    { name = "battery.settings", icon = "", label = "Battery Settings", action = "open -b com.apple.systempreferences /System/Library/PreferencePanes/Battery.prefPane" },
  }
  for _, entry in ipairs(battery_items) do
    add_bat(entry.name, { icon = entry.icon, label = entry.label, click_script = entry.action, ["label.font"] = font_small })
  end

  sbar.add("bracket", { "volume", "battery" }, {
    background = {
      color = group_bg_color,
      corner_radius = math.max(group_corner_radius, 4),
      height = math.max(widget_height + 2, 18),
      border_width = group_border_width,
      border_color = group_border_color,
    }
  })

  shell_exec(string.format("%s --trigger volume_change && %s --update volume && %s --update battery", SKETCHYBAR_BIN, SKETCHYBAR_BIN, SKETCHYBAR_BIN))
end

return { register = register }
