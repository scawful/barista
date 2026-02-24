-- Left-side bar items: front_app (and popup), control_center (optional), spaces refresh.

local popup_items = require("popup_items")

local function register(ctx)
  local sbar = ctx.sbar
  local theme = ctx.theme
  local settings = ctx.settings
  local font_string = ctx.font_string
  local PLUGIN_DIR = ctx.PLUGIN_DIR
  local widget_corner_radius = ctx.widget_corner_radius
  local widget_height = ctx.widget_height
  local popup_background = ctx.popup_background
  local hover_script_cmd = ctx.hover_script_cmd
  local popup_toggle_action = ctx.popup_toggle_action
  local attach_hover = ctx.attach_hover
  local subscribe_popup_autoclose = ctx.subscribe_popup_autoclose
  local shell_exec = ctx.shell_exec
  local SKETCHYBAR_BIN = ctx.SKETCHYBAR_BIN
  local POST_CONFIG_DELAY = ctx.POST_CONFIG_DELAY
  local associated_displays = ctx.associated_displays
  local call_script = ctx.call_script
  local FRONT_APP_ACTION_SCRIPT = ctx.FRONT_APP_ACTION_SCRIPT
  local YABAI_CONTROL_SCRIPT = ctx.YABAI_CONTROL_SCRIPT
  local refresh_spaces = ctx.refresh_spaces
  local watch_spaces = ctx.watch_spaces
  local init_spaces = ctx.init_spaces
  local yabai_available = ctx.yabai_available
  local CONFIG_DIR = ctx.CONFIG_DIR
  local control_center_module = ctx.control_center_module
  local state = ctx.state
  local WINDOW_MANAGER_MODE = ctx.WINDOW_MANAGER_MODE
  local group_bg_color = ctx.group_bg_color
  local group_border_color = ctx.group_border_color
  local group_border_width = ctx.group_border_width
  local group_corner_radius = ctx.group_corner_radius

  init_spaces()

  -- Front App indicator
  sbar.add("item", "front_app", {
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
  })
  shell_exec(string.format("sleep %.1f; %s --subscribe front_app front_app_switched", POST_CONFIG_DELAY, SKETCHYBAR_BIN))
  subscribe_popup_autoclose("front_app")
  attach_hover("front_app")
  shell_exec(string.format("sleep %.1f; %s --set front_app associated_display=%s associated_space=all", POST_CONFIG_DELAY, SKETCHYBAR_BIN, associated_displays))

  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local add_fa = popup_items.make_add(sbar, "front_app", { hover_script = hover_script_cmd, attach_hover = attach_hover })

  add_fa("front_app.header", {
    icon = "",
    label = "Application Controls",
    ["label.font"] = font_bold,
    ["label.color"] = theme.SAPPHIRE,
    background = { drawing = false },
  })

  local app_actions = {
    { name = "front_app.show", icon = "󰓇", icon_color = theme.SKY, label = "Bring to Front", action = call_script(FRONT_APP_ACTION_SCRIPT, "show"), shortcut = "⌘⇥" },
    { name = "front_app.hide", icon = "󰘔", icon_color = theme.PEACH, label = "Hide App", action = call_script(FRONT_APP_ACTION_SCRIPT, "hide"), shortcut = "⌘H" },
    { name = "front_app.quit", icon = "󰅘", icon_color = theme.RED, label = "Quit App", action = call_script(FRONT_APP_ACTION_SCRIPT, "quit"), shortcut = "⌘Q" },
    { name = "front_app.force_quit", icon = "󰜏", icon_color = theme.MAROON or theme.RED, label = "Force Quit", action = call_script(FRONT_APP_ACTION_SCRIPT, "force-quit") },
  }
  for _, entry in ipairs(app_actions) do
    add_fa(entry.name, {
      icon = { string = entry.icon, color = entry.icon_color },
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end

  add_fa("front_app.sep1", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_small,
    ["label.color"] = "0x40cdd6f4",
    background = { drawing = false },
  })

  add_fa("front_app.window_header", {
    icon = "",
    label = "Window Controls",
    ["label.font"] = font_bold,
    ["label.color"] = theme.TEAL,
    background = { drawing = false },
  })

  local window_actions = {
    { name = "front_app.window.float", icon = "󰒄", icon_color = theme.SAPPHIRE, label = "Toggle Float", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-float") },
    { name = "front_app.window.fullscreen", icon = "󰊓", icon_color = theme.GREEN, label = "Toggle Fullscreen", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-fullscreen") },
    { name = "front_app.window.sticky", icon = "󰐊", icon_color = theme.YELLOW, label = "Toggle Sticky", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-sticky") },
    { name = "front_app.window.topmost", icon = "󰁜", icon_color = theme.MAUVE or theme.LAVENDER, label = "Toggle Topmost", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-topmost") },
    { name = "front_app.window.center", icon = "󰘞", icon_color = theme.BLUE, label = "Center Window", action = call_script(YABAI_CONTROL_SCRIPT, "window-center") },
  }
  for _, entry in ipairs(window_actions) do
    add_fa(entry.name, {
      icon = { string = entry.icon, color = entry.icon_color },
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end

  add_fa("front_app.sep2", {
    icon = "",
    label = "───────────────",
    ["label.font"] = font_small,
    ["label.color"] = "0x40cdd6f4",
    background = { drawing = false },
  })

  add_fa("front_app.move_header", {
    icon = "",
    label = "Move Window",
    ["label.font"] = font_bold,
    ["label.color"] = theme.MAUVE or theme.LAVENDER,
    background = { drawing = false },
  })

  local move_actions = {
    { name = "front_app.move.display_prev", icon = "󰍺", icon_color = theme.SKY, label = "Move to Prev Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-prev") },
    { name = "front_app.move.display_next", icon = "󰍹", icon_color = theme.SKY, label = "Move to Next Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-next") },
    { name = "front_app.move.space_prev", icon = "󱂬", icon_color = theme.PEACH, label = "Move to Prev Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-prev-wrap") },
    { name = "front_app.move.space_next", icon = "󱂬", icon_color = theme.PEACH, label = "Move to Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-next-wrap") },
  }
  for _, entry in ipairs(move_actions) do
    add_fa(entry.name, {
      icon = { string = entry.icon, color = entry.icon_color },
      label = entry.label,
      click_script = entry.action,
      ["label.font"] = font_small,
    })
  end

  -- Spaces: refresh and watch
  refresh_spaces()
  if yabai_available() then
    watch_spaces()
  end
  shell_exec(string.format("%s --trigger space_change", SKETCHYBAR_BIN))
  shell_exec(string.format("%s --trigger space_mode_refresh", SKETCHYBAR_BIN))
  shell_exec(string.format("sleep 1.2; CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR))

  -- Control Center (when enabled)
  if control_center_module then
    local cc_widget = control_center_module.create_widget({
      position = "left",
      icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
      label_font = font_string(settings.font.text, settings.font.style_map["Bold"], 11),
      label_color = "0xffcdd6f4",
      show_label = true,
      update_freq = 30,
      script_path = PLUGIN_DIR .. "/control_center.sh",
      height = widget_height,
      popup_background = popup_background(),
      state = state,
      window_manager_mode = WINDOW_MANAGER_MODE,
      popup_toggle_script = popup_toggle_action(),
    })

    local control_center_item_name = cc_widget.name or "control_center"
    cc_widget.name = nil
    sbar.add("item", control_center_item_name, cc_widget)

    shell_exec(string.format("sleep %.1f; %s --move control_center before front_app 2>/dev/null || true", POST_CONFIG_DELAY, SKETCHYBAR_BIN))

    if cc_widget.script and cc_widget.script ~= "" then
      sbar.exec(string.format("NAME=%s %s", control_center_item_name, cc_widget.script))
    end

    local cc_popup_items = control_center_module.create_popup_items(sbar, theme, font_string, settings, {
      state = state,
      window_manager_mode = WINDOW_MANAGER_MODE,
    })
    for _, popup_item in ipairs(cc_popup_items) do
      local item_name = popup_item.name
      popup_item.name = nil
      if not popup_item.script then
        popup_item.script = hover_script_cmd
      end
      sbar.add("item", item_name, popup_item)
      attach_hover(item_name)
    end

    shell_exec(string.format("sleep %.1f; %s --subscribe control_center mouse.entered mouse.exited space_change space_mode_refresh system_woke", POST_CONFIG_DELAY, SKETCHYBAR_BIN))
    subscribe_popup_autoclose("control_center")
    attach_hover("control_center")
    shell_exec(string.format("sleep %.1f; %s --set control_center associated_display=%s associated_space=all", POST_CONFIG_DELAY, SKETCHYBAR_BIN, associated_displays))

    sbar.add("bracket", { "control_center", "front_app" }, {
      background = {
        color = group_bg_color,
        corner_radius = math.max(group_corner_radius, 4),
        height = math.max(widget_height + 2, 18),
        border_width = group_border_width,
        border_color = group_border_color,
      }
    })
  end
end

return { register = register }
