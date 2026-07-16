-- Right-side bar items: lmstudio, clock, calendar, system_info, volume, battery, brackets.

local interface_extensions = require("interface_extensions")
local popup_items = require("popup_items")
local ui = require("ui_builder")

local function get_layout(ctx)
  local factory = ctx.widget_factory
  local settings = ctx.settings
  local theme = ctx.theme
  local font_string = ctx.font_string
  local PLUGIN_DIR = ctx.PLUGIN_DIR
  local widget_height = ctx.widget_height
  local popup_background = ctx.popup_background
  local hover_script_cmd = ctx.hover_script_cmd
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
  local shell_quote = ctx.shell_quote or function(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
  end
  local compiled_script = ctx.compiled_script
  local widget_daemon_enabled = ctx.widget_daemon_enabled == true
  local hover_color = ctx.hover_color
  local hover_animation_curve = ctx.hover_animation_curve
  local hover_animation_duration = ctx.hover_animation_duration
  local SCRIPTS_DIR = ctx.SCRIPTS_DIR or ""
  local CONFIG_DIR = ctx.CONFIG_DIR or ((os.getenv("HOME") or "") .. "/.config/sketchybar")
  local code_dir = ctx.CODE_DIR or (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or ((os.getenv("HOME") or "") .. "/src"))

  local layout = {}
  local right_group_children = {}

  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end
  local media_control_script = SCRIPTS_DIR ~= "" and (SCRIPTS_DIR .. "/media_control.sh") or ""
  local function close_popup_after(item_name, command)
    return ui.close_after(item_name, command, { sketchybar_bin = SKETCHYBAR_BIN })
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
  local function compact_string_list(values)
    if type(values) == "string" and values:match("%S") then
      return values
    end
    if type(values) ~= "table" then
      return nil
    end
    local result = {}
    for _, value in ipairs(values) do
      if type(value) == "string" and value:match("%S") then
        table.insert(result, value)
      end
    end
    if #result == 0 then
      return nil
    end
    return table.concat(result, ":")
  end

  -- LM Studio quick selector
  local lmstudio_enabled = type(state.widgets) == "table" and state.widgets.lmstudio == true
  if lmstudio_enabled then
    local lmstudio_script = PLUGIN_DIR .. "/lmstudio_model.sh"
    table.insert(layout, factory.create_item("lmstudio", {
      position = "right",
      drawing = true,
      icon = {
        string = "󰭻",
        color = tc("SUBTEXT1", "WHITE"),
        padding_left = 6,
        padding_right = 4,
      },
      label = {
        string = "off",
        color = tc("SUBTEXT1", "WHITE"),
        padding_left = 2,
        padding_right = 8,
        font = font_small,
      },
      update_freq = 20,
      script = lmstudio_script,
      click_script = ui.toggle_then_refresh_async("lmstudio", lmstudio_script, { sketchybar_bin = SKETCHYBAR_BIN }),
      background = {
        color = theme.BG_SEC_COLR or "0x18313a46",
        corner_radius = math.max(group_corner_radius, 4),
        height = widget_height,
      },
      popup = {
        align = "right",
        background = popup_background(),
      },
    }))
    table.insert(right_group_children, "lmstudio")
    table.insert(layout, { action = "subscribe_popup_autoclose", name = "lmstudio" })
    table.insert(layout, { action = "attach_hover", name = "lmstudio" })
    table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --subscribe lmstudio system_woke", POST_CONFIG_DELAY, SKETCHYBAR_BIN) })

    local add_lm = popup_items.make_add("lmstudio", { hover_script = hover_script_cmd })
    table.insert(layout, add_lm("lmstudio.header", {
      icon = "",
      label = "LM Studio",
      ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
      background = { drawing = false },
    }))
    table.insert(layout, add_lm("lmstudio.state", {
      icon = "󰭻",
      label = "No models loaded",
      click_script = close_popup_after("lmstudio", build_script_action(lmstudio_script, "open_current")),
      ["label.font"] = font_small,
      background = { drawing = false },
    }))
    table.insert(layout, add_lm("lmstudio.open", {
      icon = "󰆍",
      label = "Open LM Studio",
      click_script = close_popup_after("lmstudio", build_script_action(lmstudio_script, "open")),
      ["label.font"] = font_small,
    }))
    table.insert(layout, add_lm("lmstudio.sep0", {
      icon = "",
      label = "───────────────",
      ["label.font"] = font_small,
      ["label.color"] = "0x40cdd6f4",
      background = { drawing = false },
    }))

    local lmstudio_extension_actions = interface_extensions.for_surface(CONFIG_DIR, code_dir, state, "lmstudio")
    if #lmstudio_extension_actions > 0 then
      table.insert(layout, add_lm("lmstudio.presets.header", {
        icon = "",
        label = "Presets",
        ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
        ["label.color"] = tc("TEAL"),
        background = { drawing = false },
      }))
      for _, entry in ipairs(lmstudio_extension_actions) do
        if entry.action and entry.action ~= "" then
          table.insert(layout, add_lm("lmstudio.extension." .. entry.id, {
            icon = entry.icon or "󰐕",
            label = entry.label,
            click_script = close_popup_after("lmstudio", entry.action),
            ["label.font"] = font_small,
            ["label.color"] = entry.label_color,
          }))
        end
      end
      table.insert(layout, add_lm("lmstudio.sep1", {
        icon = "",
        label = "───────────────",
        ["label.font"] = font_small,
        ["label.color"] = "0x40cdd6f4",
        background = { drawing = false },
      }))
    end

    table.insert(layout, add_lm("lmstudio.model.off", {
      icon = "󰤂",
      label = "Unload All",
      click_script = close_popup_after("lmstudio", build_script_action(lmstudio_script, "off")),
      ["label.font"] = font_small,
    }))
  end

  local calendar_state = type(state.menus) == "table" and type(state.menus.calendar) == "table"
    and state.menus.calendar
    or {}
  local calendar_task_sources = compact_string_list(calendar_state.task_sources)
  local meeting_cache_max_age_seconds = tonumber(calendar_state.meeting_cache_max_age_seconds) or 86400
  if meeting_cache_max_age_seconds <= 0 then
    meeting_cache_max_age_seconds = 86400
  end
  meeting_cache_max_age_seconds = math.floor(meeting_cache_max_age_seconds)
  local calendar_script = env_prefix({
    BARISTA_CALENDAR_TASK_SOURCES = calendar_task_sources,
    BARISTA_TASK_PROVIDER = type(calendar_state.task_provider) == "string" and calendar_state.task_provider or nil,
    BARISTA_SYSHELP_BIN = type(calendar_state.syshelp_path) == "string" and calendar_state.syshelp_path or nil,
    BARISTA_CALENDAR_MEETING_CACHE = type(calendar_state.meeting_cache_file) == "string"
      and calendar_state.meeting_cache_file:match("%S")
      and calendar_state.meeting_cache_file
      or nil,
    BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS = tostring(meeting_cache_max_age_seconds),
  }) .. PLUGIN_DIR .. "/calendar.sh"

  -- Clock
  table.insert(layout, factory.create_clock({
    icon = icon_for("clock", "󰥔"),
    script = compiled_script("clock_widget", PLUGIN_DIR .. "/clock.sh"),
    update_freq = widget_daemon_enabled and false or 30,
    daemon_managed = widget_daemon_enabled,
    click_script = ui.toggle_then_refresh_async("clock", calendar_script, { sketchybar_bin = SKETCHYBAR_BIN }),
    popup = {
      align = "right",
      background = popup_background()
    }
  }))
  table.insert(right_group_children, "clock")
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "clock" })
  table.insert(layout, { action = "attach_hover", name = "clock" })

  local task_focus_enabled = type(state.widgets) == "table"
    and state.widgets.task_focus == true
    and calendar_task_sources ~= nil
  if task_focus_enabled then
    local task_provider = type(calendar_state.task_provider) == "string"
      and calendar_state.task_provider:match("%S")
      and calendar_state.task_provider
      or "files"
    local task_env = env_prefix({
      BARISTA_CALENDAR_TASK_SOURCES = calendar_task_sources,
      BARISTA_CAPTURE_SECTION = type(calendar_state.capture_section) == "string"
        and calendar_state.capture_section:match("%S")
        and calendar_state.capture_section
        or nil,
      BARISTA_CAPTURE_STATE = type(calendar_state.capture_state) == "string"
        and calendar_state.capture_state:match("%S")
        and calendar_state.capture_state
        or nil,
      BARISTA_TASK_PROVIDER = task_provider,
      BARISTA_SYSHELP_BIN = type(calendar_state.syshelp_path) == "string"
        and calendar_state.syshelp_path:match("%S")
        and calendar_state.syshelp_path
        or nil,
    })
    -- Task helpers ship with Barista and must not follow the optional external
    -- yabai-control scripts override.
    local task_scripts_dir = CONFIG_DIR .. "/scripts"
    local task_pulse_command = task_env .. build_script_action(PLUGIN_DIR .. "/task_pulse.sh")
    local task_capture_command = task_env .. build_script_action(task_scripts_dir .. "/task_capture.sh")
    local task_open_command = task_env .. build_script_action(task_scripts_dir .. "/task_action.sh", "open")
    local focus_session_command = shell_quote(task_scripts_dir .. "/focus_session.py") .. " toggle 25"
      .. " >/dev/null 2>&1 && " .. shell_quote(SKETCHYBAR_BIN) .. " --trigger task_state_changed"

    ui.anchor(layout, {
      ctx = ctx,
      name = "task_focus",
      events = { "task_state_changed", "system_woke" },
      props = ui.apply_anchor_chip({
        position = "right",
        drawing = true,
        icon = {
          string = "󰄱",
          color = tc("SKY"),
          padding_left = 6,
          padding_right = 3,
        },
        label = {
          string = "Tasks",
          color = tc("WHITE"),
          padding_left = 2,
          padding_right = 7,
          font = font_small,
        },
        script = task_pulse_command,
        click_script = ui.toggle_then_refresh_async("task_focus", task_pulse_command, {
          sketchybar_bin = SKETCHYBAR_BIN,
        }),
        popup = {
          align = "right",
          background = popup_background(),
        },
      }, ctx, {
        corner_radius = math.max(group_corner_radius, 4),
        height = widget_height,
      }),
    })
    table.insert(right_group_children, "task_focus")

    local add_task = popup_items.make_add("task_focus", { hover_script = hover_script_cmd })
    local task_status_rows = {
      { name = "task_focus.summary", icon = "󰄱", label = "Tasks: …", color = tc("LAVENDER") },
      { name = "task_focus.focus", icon = "󰓾", label = "Focus: —", color = tc("WHITE") },
      { name = "task_focus.next", icon = "󰒭", label = "Next: —", color = tc("SKY") },
      { name = "task_focus.waiting", icon = "󰔟", label = "Waiting: Clear", color = tc("YELLOW") },
      { name = "task_focus.blocked", icon = "󰅖", label = "Blocked: Clear", color = tc("RED") },
    }
    for _, entry in ipairs(task_status_rows) do
      table.insert(layout, add_task(entry.name, {
        icon = entry.icon,
        label = entry.label,
        ["label.font"] = font_small,
        ["label.color"] = entry.color,
        background = { drawing = false },
      }))
    end

    local task_actions = {
      {
        name = "task_focus.capture",
        icon = "󰐕",
        label = "Capture Task",
        click_script = close_popup_after("task_focus", task_capture_command),
      },
      {
        name = "task_focus.open",
        icon = "󰈙",
        label = "Open Board",
        click_script = close_popup_after("task_focus", task_open_command),
      },
      {
        name = "task_focus.timer",
        icon = "󰔛",
        label = "Start 25m Focus",
        click_script = close_popup_after("task_focus", focus_session_command),
      },
    }
    for _, entry in ipairs(task_actions) do
      table.insert(layout, add_task(entry.name, {
        icon = entry.icon,
        label = entry.label,
        click_script = entry.click_script,
        ["label.font"] = font_small,
        hover = true,
      }))
    end
  end

  -- Calendar popup items (tc = theme color with fallback for themes that omit accent keys)
  local calendar_items = {
    { name = "clock.calendar.header", icon = "", script = calendar_script, font_style = "Semibold", color = tc("LAVENDER"), ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small) },
    { name = "clock.calendar.weekdays", icon = "", font_style = "Bold", color = theme.DARK_WHITE or theme.WHITE },
  }
  for i = 1, 6 do
    table.insert(calendar_items, { name = string.format("clock.calendar.week%d", i), icon = "", font_style = "Regular", color = theme.WHITE })
  end
  table.insert(calendar_items, { name = "clock.calendar.summary", icon = "", font_style = "Semibold", color = tc("YELLOW") })
  table.insert(calendar_items, { name = "clock.calendar.meeting.next", icon = "󰃰", text_row = true, font_style = "Regular", color = tc("MAUVE", "LAVENDER") })
  table.insert(calendar_items, { name = "clock.calendar.tasks.today", icon = "", font_style = "Regular", color = theme.WHITE })
  table.insert(calendar_items, { name = "clock.calendar.tasks.next", icon = "", font_style = "Regular", color = tc("SKY") })
  table.insert(calendar_items, { name = "clock.calendar.tasks.waiting", icon = "", font_style = "Regular", color = tc("YELLOW") })
  table.insert(calendar_items, { name = "clock.calendar.tasks.blocked", icon = "", font_style = "Regular", color = tc("YELLOW") })
  table.insert(calendar_items, { name = "clock.calendar.weekend", icon = "", font_style = "Regular", color = tc("SKY") })
  table.insert(calendar_items, { name = "clock.calendar.progress", icon = "", font_style = "Regular", color = theme.DARK_WHITE or theme.WHITE })
  table.insert(calendar_items, { name = "clock.calendar.footer", icon = "", font_style = "Regular", color = theme.DARK_WHITE or theme.WHITE })

  for _, item in ipairs(calendar_items) do
    local is_header = item.name == "clock.calendar.header"
    local is_summary = item.name == "clock.calendar.summary"
    local is_footer = item.name == "clock.calendar.footer"
    local is_task_row = item.name:match("^clock%.calendar%.tasks%.") ~= nil
    local is_text_row = item.text_row == true or is_header or is_summary or is_footer or is_task_row or item.name == "clock.calendar.weekend" or item.name == "clock.calendar.progress"
    local item_font = settings.font.numbers
    if is_text_row then item_font = settings.font.text end
    local opts = {
      position = "popup.clock",
      icon = item.icon or "",
      label = "",
      ["label.font"] = font_string(item_font, settings.font.style_map[item.font_style or "Regular"] or settings.font.style_map["Regular"], is_header and settings.font.sizes.text or settings.font.sizes.small),
      ["label.color"] = item.color or theme.WHITE,
      ["icon.font"] = item["icon.font"] or font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small),
      ["icon.color"] = item.color or theme.WHITE,
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
    BARISTA_SKETCHYBAR_BIN = SKETCHYBAR_BIN,
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
    click_script = ui.toggle_then_refresh_async("system_info", system_info_script .. " popup_refresh", { sketchybar_bin = SKETCHYBAR_BIN }),
  }))
  table.insert(right_group_children, "system_info")
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
  table.insert(system_info_items, { name = "system_info.settings", icon = "", label = "System Settings", action = "open -b com.apple.systempreferences" })

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

  if #right_group_children > 0 then
    table.insert(layout, factory.create_bracket("right_group_1", right_group_children, {
      background = {
        color = group_bg_color,
        corner_radius = math.max(group_corner_radius, 4),
        height = math.max(widget_height + 2, 18),
        border_width = group_border_width,
        border_color = group_border_color,
      }
    }))
  end

  -- Volume
  local volume_env = env_prefix({
    BARISTA_CONFIG_DIR = CONFIG_DIR,
    BARISTA_RUNTIME_CONTEXT_DIR = CONFIG_DIR .. "/cache/runtime_context",
    BARISTA_SKETCHYBAR_BIN = SKETCHYBAR_BIN,
    BARISTA_ICON_VOLUME = state_module.get_icon(state, "volume", ""),
    BARISTA_VOLUME_OK = tc("GREEN"),
    BARISTA_VOLUME_WARN = tc("YELLOW"),
    BARISTA_VOLUME_LOW = tc("RED"),
    BARISTA_VOLUME_MUTE = tc("BLUE"),
    BARISTA_VOLUME_OUTPUT_IDLE = tc("WHITE"),
    BARISTA_MEDIA_LABEL_MAX = "72",
    BARISTA_HOVER_COLOR = tostring(hover_color),
    BARISTA_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
    BARISTA_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
  })
  local volume_script = volume_env .. PLUGIN_DIR .. "/volume.sh"
  local volume_popup_helper = compiled_script("volume_popup_helper", "")
  local volume_popup_refresh = volume_script .. " popup_refresh"
  if type(volume_popup_helper) == "string" and volume_popup_helper ~= "" then
    volume_popup_refresh = volume_env .. shell_quote(volume_popup_helper)
      .. " popup_refresh || " .. volume_script .. " popup_refresh"
  end
  table.insert(layout, factory.create_volume({
    script = volume_script,
    click_script = ui.toggle_then_refresh_async("volume", volume_popup_refresh, { sketchybar_bin = SKETCHYBAR_BIN }),
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
    label = "Volume: …",
    ["label.font"] = font_small,
    background = { drawing = false },
  }))
  table.insert(layout, add_vol("volume.output", {
    icon = "󰓃",
    label = "Output: …",
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
    label = "Now Playing: Nothing",
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
  local battery_script = battery_env .. PLUGIN_DIR .. "/battery.sh " .. tc("GREEN") .. " " .. tc("YELLOW") .. " " .. tc("RED") .. " " .. tc("BLUE")
  table.insert(layout, factory.create_battery({
    script = battery_script,
    update_freq = widget_daemon_enabled and false or 120,
    daemon_managed = widget_daemon_enabled,
    click_script = ui.toggle_then_refresh_async("battery", battery_script .. " popup_refresh", { sketchybar_bin = SKETCHYBAR_BIN }),
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

  table.insert(layout, {
    action = "exec",
    cmd = string.format("sleep %.1f; %s --trigger volume_change && NAME=battery SENDER=routine %s", POST_CONFIG_DELAY, SKETCHYBAR_BIN, battery_script),
  })

  return layout
end

return { get_layout = get_layout }
