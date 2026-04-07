-- Left-side bar items: front_app (and popup), control_center (optional), spaces refresh.

local popup_items = require("popup_items")

local function get_layout(ctx)
  local current_time_ms = ctx.current_time_ms or function()
    return math.floor(os.clock() * 1000)
  end
  local factory = ctx.widget_factory
  local settings = ctx.settings
  local theme = ctx.theme
  local font_string = ctx.font_string
  local PLUGIN_DIR = ctx.PLUGIN_DIR
  local widget_corner_radius = ctx.widget_corner_radius
  local widget_height = ctx.widget_height
  local popup_background = ctx.popup_background
  local hover_script_cmd = ctx.hover_script_cmd
  local triforce_hover_script_cmd = ctx.triforce_hover_script_cmd or hover_script_cmd
  local popup_toggle_action = ctx.popup_toggle_action
  local POST_CONFIG_DELAY = ctx.POST_CONFIG_DELAY
  local SPACE_POST_CONFIG_DELAY = ctx.SPACE_POST_CONFIG_DELAY or POST_CONFIG_DELAY
  local SKETCHYBAR_BIN = ctx.SKETCHYBAR_BIN
  local associated_displays = ctx.associated_displays
  local FRONT_APP_ACTION_SCRIPT = ctx.FRONT_APP_ACTION_SCRIPT
  local YABAI_CONTROL_SCRIPT = ctx.YABAI_CONTROL_SCRIPT
  local call_script = ctx.call_script
  local CONFIG_DIR = ctx.CONFIG_DIR
  local control_center_module = ctx.control_center_module
  local oracle_module = ctx.integrations and ctx.integrations.oracle or nil
  local state = ctx.state
  local WINDOW_MANAGER_MODE = ctx.WINDOW_MANAGER_MODE
  local group_bg_color = ctx.group_bg_color
  local group_border_color = ctx.group_border_color
  local group_border_width = ctx.group_border_width
  local group_corner_radius = ctx.group_corner_radius or 4
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end

  local layout = {}
  local metrics = {
    front_app_ms = 0,
    triforce_ms = 0,
    spaces_ms = 0,
    control_center_ms = 0,
    group_ms = 0,
  }
  local triforce_present = false
  local triforce_name = "triforce"
  local control_center_item_name = nil
  local yabai_ready = type(ctx.yabai_available) == "function" and ctx.yabai_available()
  local window_manager_enabled = WINDOW_MANAGER_MODE ~= "disabled"
  local oracle_menu_model = nil
  local control_center_status = nil

  -- Front App indicator
  local front_app_start_ms = current_time_ms()
  table.insert(layout, factory.create_item("front_app", {
    position = "left",
    icon = { drawing = true },
    label = { drawing = true },
    script = PLUGIN_DIR .. "/front_app.sh",
    click_script = popup_toggle_action(),
    background = {
      color = "0x00000000",
      corner_radius = widget_corner_radius,
      height = widget_height,
    },
    popup = {
      align = "left",
      background = popup_background()
    }
  }))

  -- Subscriptions and effects for front_app
  table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --subscribe front_app front_app_switched", POST_CONFIG_DELAY, SKETCHYBAR_BIN) })
  table.insert(layout, { action = "subscribe_popup_autoclose", name = "front_app" })
  table.insert(layout, { action = "attach_hover", name = "front_app" })
  table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --set front_app associated_display=%s associated_space=all", POST_CONFIG_DELAY, SKETCHYBAR_BIN, associated_displays) })

  if oracle_module and type(oracle_module.create_triforce_widget) == "function" then
    local triforce_start_ms = current_time_ms()
    if type(oracle_module.build_menu_model) == "function" then
      oracle_menu_model = oracle_module.build_menu_model(ctx)
    end
    local triforce_widget = oracle_module.create_triforce_widget({
      ctx = ctx,
      model = oracle_menu_model,
      position = "left",
      popup_toggle_script = popup_toggle_action("triforce", { direct = true }),
      popup_background = popup_background(),
      background = {
        color = "0x00000000",
        corner_radius = widget_corner_radius,
        height = widget_height,
      },
      icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
    })

    if triforce_widget then
      triforce_name = triforce_widget.name or "triforce"
      triforce_widget.name = nil
      table.insert(layout, { type = "item", name = triforce_name, props = triforce_widget })
      table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --move %s before front_app 2>/dev/null || true", POST_CONFIG_DELAY, SKETCHYBAR_BIN, triforce_name) })
      if triforce_widget.script and triforce_widget.script ~= "" then
        table.insert(layout, { action = "exec", cmd = string.format("NAME=%s %s", triforce_name, triforce_widget.script) })
        table.insert(layout, {
          action = "exec",
          cmd = string.format("sleep %.1f; NAME=%s %s", POST_CONFIG_DELAY, triforce_name, triforce_widget.script),
        })
      end
      table.insert(layout, {
        action = "exec",
        cmd = string.format(
          "sleep %.1f; %s --subscribe %s system_woke",
          POST_CONFIG_DELAY,
          SKETCHYBAR_BIN,
          triforce_name
        ),
      })
      table.insert(layout, { action = "subscribe_popup_autoclose", name = triforce_name })
      table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --set %s associated_display=%s associated_space=all", POST_CONFIG_DELAY, SKETCHYBAR_BIN, triforce_name, associated_displays) })

      if type(oracle_module.create_triforce_popup_items) == "function" then
        local popup_ctx = ctx
        if oracle_menu_model then
          popup_ctx = setmetatable({ oracle_menu_model = oracle_menu_model }, { __index = ctx })
        end
        local triforce_popup_items = oracle_module.create_triforce_popup_items(popup_ctx)
        table.insert(layout, {
          action = "call",
          fn = function()
            if not ctx.sbar or type(ctx.sbar.remove) ~= "function" then
              return
            end
            for _, popup_item in ipairs(triforce_popup_items or {}) do
              local popup_name = popup_item.name
              if popup_name and popup_name ~= "" then
                pcall(function()
                  ctx.sbar.remove(popup_name)
                end)
              end
            end
          end,
        })
        for _, popup_item in ipairs(triforce_popup_items or {}) do
          local item_name = popup_item.name
          popup_item.name = nil
          local should_hover = popup_item.hover == true
          popup_item.hover = nil
          if should_hover and not popup_item.script then
            popup_item.script = triforce_hover_script_cmd
          end
          table.insert(layout, { type = "item", name = item_name, props = popup_item, attach_hover = should_hover })
        end
      end

      triforce_present = true
    end
    metrics.triforce_ms = current_time_ms() - triforce_start_ms
  end

  -- Front App Popup Items
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local yabai_controls_enabled = window_manager_enabled and yabai_ready and YABAI_CONTROL_SCRIPT and YABAI_CONTROL_SCRIPT ~= ""
  local function close_front_app_after(command)
    if not command or command == "" then
      return "sketchybar -m --set front_app popup.drawing=off"
    end
    return command .. "; sketchybar -m --set front_app popup.drawing=off"
  end

  local add_fa = popup_items.make_add("front_app", { hover_script = hover_script_cmd })

  table.insert(layout, add_fa("front_app.header", {
    icon = "",
    label = "App Controls",
    ["label.font"] = font_bold,
    ["label.color"] = tc("SAPPHIRE"),
    background = { drawing = false },
  }))

  table.insert(layout, add_fa("front_app.state", {
    icon = { string = "󰆾", color = tc("TEAL") },
    label = "Tiled · Normal",
    ["label.font"] = font_small,
    ["label.color"] = tc("SUBTEXT1", "WHITE"),
    background = { drawing = false },
  }))

  table.insert(layout, add_fa("front_app.location", {
    icon = { string = "󰍹", color = tc("SKY") },
    label = "Space ? · Display ?",
    ["label.font"] = font_small,
    ["label.color"] = tc("SUBTEXT1", "WHITE"),
    background = { drawing = false },
  }))

  table.insert(layout, add_fa("front_app.sep0", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_small,
    ["label.color"] = "0x40cdd6f4",
    background = { drawing = false },
  }))

  table.insert(layout, add_fa("front_app.app_header", {
    icon = "",
    label = "App",
    ["label.font"] = font_bold,
    ["label.color"] = tc("PEACH"),
    background = { drawing = false },
  }))

  local app_actions = {
    { name = "front_app.hide", icon = "󰘔", icon_color = tc("PEACH"), label = "Hide App", action = call_script(FRONT_APP_ACTION_SCRIPT, "hide"), shortcut = "⌘H" },
    { name = "front_app.quit", icon = "󰅘", icon_color = tc("RED"), label = "Quit App", action = call_script(FRONT_APP_ACTION_SCRIPT, "quit"), shortcut = "⌘Q" },
    { name = "front_app.force_quit", icon = "󰜏", icon_color = tc("MAROON", "RED"), label = "Force Quit", action = call_script(FRONT_APP_ACTION_SCRIPT, "force-quit") },
  }
  for _, entry in ipairs(app_actions) do
    table.insert(layout, add_fa(entry.name, {
      icon = { string = entry.icon, color = entry.icon_color },
      label = entry.label,
      click_script = close_front_app_after(entry.action),
      ["label.font"] = font_small,
    }))
  end

  table.insert(layout, add_fa("front_app.sep1", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_small,
    ["label.color"] = "0x40cdd6f4",
    background = { drawing = false },
  }))

  table.insert(layout, add_fa("front_app.window_header", {
    icon = "",
    label = "Window",
    ["label.font"] = font_bold,
    ["label.color"] = tc("TEAL"),
    background = { drawing = false },
  }))

  if yabai_controls_enabled then
    local window_actions = {
      { name = "front_app.window.float", icon = "󰒄", icon_color = tc("SAPPHIRE"), label = "Toggle Float", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-float") },
      { name = "front_app.window.adopt_space_mode", icon = "󰆾", icon_color = tc("TEAL"), label = "Adopt Current Space Mode", action = call_script(YABAI_CONTROL_SCRIPT, "window-adopt-space-mode") },
      { name = "front_app.window.fullscreen", icon = "󰊓", icon_color = tc("GREEN"), label = "Toggle Fullscreen", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-fullscreen") },
      { name = "front_app.window.sticky", icon = "󰐊", icon_color = tc("YELLOW"), label = "Toggle Sticky", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-sticky") },
      { name = "front_app.window.topmost", icon = "󰁜", icon_color = tc("MAUVE", "LAVENDER"), label = "Toggle Topmost", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-topmost") },
      { name = "front_app.window.center", icon = "󰘞", icon_color = tc("BLUE"), label = "Center Window", action = call_script(YABAI_CONTROL_SCRIPT, "window-center") },
    }
    for _, entry in ipairs(window_actions) do
      table.insert(layout, add_fa(entry.name, {
        icon = { string = entry.icon, color = entry.icon_color },
        label = entry.label,
        click_script = close_front_app_after(entry.action),
        ["label.font"] = font_small,
      }))
    end

    table.insert(layout, add_fa("front_app.sep2", {
      icon = "",
      label = "───────────────",
      ["label.font"] = font_small,
      ["label.color"] = "0x40cdd6f4",
      background = { drawing = false },
    }))

    table.insert(layout, add_fa("front_app.move_header", {
      icon = "",
      label = "Move",
      ["label.font"] = font_bold,
      ["label.color"] = tc("MAUVE", "LAVENDER"),
      background = { drawing = false },
    }))

    local move_actions = {
      { name = "front_app.move.float_space", icon = "󰒄", icon_color = tc("TEAL"), label = "Send to Float Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-float") },
      { name = "front_app.move.display_prev", icon = "󰍺", icon_color = tc("SKY"), label = "Move to Prev Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-prev") },
      { name = "front_app.move.display_next", icon = "󰍹", icon_color = tc("SKY"), label = "Move to Next Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-next") },
      { name = "front_app.move.space_prev", icon = "󱂬", icon_color = tc("PEACH"), label = "Move to Prev Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-prev-wrap") },
      { name = "front_app.move.space_next", icon = "󱂬", icon_color = tc("PEACH"), label = "Move to Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-next-wrap") },
    }
    for _, entry in ipairs(move_actions) do
      table.insert(layout, add_fa(entry.name, {
        icon = { string = entry.icon, color = entry.icon_color },
        label = entry.label,
        click_script = close_front_app_after(entry.action),
        ["label.font"] = font_small,
      }))
    end
  else
    local unavailable_label = WINDOW_MANAGER_MODE == "disabled"
      and "Window manager disabled for this profile"
      or "Yabai unavailable - run doctor"
    local unavailable_action = (WINDOW_MANAGER_MODE ~= "disabled" and call_script(YABAI_CONTROL_SCRIPT, "doctor", "--fix")) or ""
    table.insert(layout, add_fa("front_app.window.unavailable", {
      icon = { string = "󰚌", color = tc("YELLOW") },
      label = unavailable_label,
      click_script = close_front_app_after(unavailable_action),
      ["label.font"] = font_small,
      ["label.color"] = tc("SUBTEXT1", "WHITE"),
    }))
  end
  metrics.front_app_ms = current_time_ms() - front_app_start_ms

  -- Spaces: refresh and watch
  local spaces_start_ms = current_time_ms()
  table.insert(layout, {
    action = "exec",
    cmd = string.format("sleep %.1f; CONFIG_DIR=%q %q", SPACE_POST_CONFIG_DELAY, CONFIG_DIR, PLUGIN_DIR .. "/refresh_spaces.sh"),
  })
  if ctx.yabai_available() then
    table.insert(layout, { action = "call", fn = ctx.watch_spaces })
  end
  metrics.spaces_ms = current_time_ms() - spaces_start_ms

  -- Control Center (when enabled)
  if control_center_module then
    local control_center_start_ms = current_time_ms()
    local cc_config = {
      item_name = ctx.control_center_item_name,
      position = "left",
      icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
      label_font = font_string(settings.font.text, settings.font.style_map["Bold"], 11),
      label_color = "0xffcdd6f4",
      show_label = true,
      update_freq = 30,
      config_dir = CONFIG_DIR,
      scripts_dir = ctx.SCRIPTS_DIR,
      script_path = PLUGIN_DIR .. "/control_center.sh",
      height = widget_height,
      popup_background = popup_background(),
      state = state,
      window_manager_mode = WINDOW_MANAGER_MODE,
      popup_toggle_script = popup_toggle_action(),
    }
    if type(control_center_module.get_status) == "function" then
      control_center_status = control_center_module.get_status(cc_config)
      cc_config.status = control_center_status
      cc_config.window_manager_flags = control_center_status.window_manager
      cc_config.layout = control_center_status.layout
    end
    
    -- In declarative mode, control_center_module.create_widget should return a table
    local cc_widget = control_center_module.create_widget(cc_config)
    control_center_item_name = cc_widget.name or "control_center"
    cc_widget.name = nil
    table.insert(layout, { type = "item", name = control_center_item_name, props = cc_widget })

    table.insert(layout, {
      action = "exec",
      cmd = string.format("sleep %.1f; %s --move %s before front_app 2>/dev/null || true",
                          POST_CONFIG_DELAY, SKETCHYBAR_BIN, control_center_item_name)
    })

    if cc_widget.script and cc_widget.script ~= "" then
      table.insert(layout, { action = "exec", cmd = string.format("NAME=%s %s", control_center_item_name, cc_widget.script) })
    end

    local cc_popup_items = control_center_module.create_popup_items(nil, theme, font_string, settings, {
      item_name = control_center_item_name,
      config_dir = CONFIG_DIR,
      scripts_dir = ctx.SCRIPTS_DIR,
      state = state,
      window_manager_mode = WINDOW_MANAGER_MODE,
      window_manager_flags = control_center_status and control_center_status.window_manager or nil,
    })
    for _, popup_item in ipairs(cc_popup_items) do
      local item_name = popup_item.name
      popup_item.name = nil
      local should_hover = popup_item.hover == true
      if should_hover and not popup_item.script then
        popup_item.script = hover_script_cmd
      end
      table.insert(layout, { type = "item", name = item_name, props = popup_item, attach_hover = should_hover })
    end

    if cc_widget.script and cc_widget.script ~= "" then
      table.insert(layout, {
        action = "exec",
        cmd = string.format("sleep %.1f; NAME=%s %s", POST_CONFIG_DELAY, control_center_item_name, cc_widget.script),
      })
    end

    table.insert(layout, {
      action = "exec",
      cmd = string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited space_active_refresh space_mode_refresh system_woke",
                          POST_CONFIG_DELAY, SKETCHYBAR_BIN, control_center_item_name)
    })
    table.insert(layout, { action = "subscribe_popup_autoclose", name = control_center_item_name })
    table.insert(layout, { action = "attach_hover", name = control_center_item_name })
    table.insert(layout, {
      action = "exec",
      cmd = string.format("sleep %.1f; %s --set %s associated_display=%s associated_space=all",
                          POST_CONFIG_DELAY, SKETCHYBAR_BIN, control_center_item_name, associated_displays)
    })
    metrics.control_center_ms = current_time_ms() - control_center_start_ms

  end

  local group_start_ms = current_time_ms()
  local left_group_children = {}
  if control_center_item_name then
    table.insert(left_group_children, control_center_item_name)
  end
  if triforce_present then
    table.insert(left_group_children, triforce_name)
  end
  table.insert(left_group_children, "front_app")

  if #left_group_children > 1 then
    table.insert(layout, factory.create_bracket("left_group", left_group_children, {
      background = {
        color = group_bg_color,
        corner_radius = math.max(group_corner_radius, 4),
        height = math.max(widget_height + 2, 18),
        border_width = group_border_width,
        border_color = group_border_color,
      }
    }))
  end
  metrics.group_ms = current_time_ms() - group_start_ms

  return layout, metrics
end

return { get_layout = get_layout }
