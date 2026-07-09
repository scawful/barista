-- Left-side bar items: front_app (and popup), control_center (optional), spaces refresh.

local interface_extensions = require("interface_extensions")
local ui = require("ui_builder")

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
  local music_module = ctx.integrations and ctx.integrations.music or nil
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
    music_ms = 0,
    spaces_ms = 0,
    control_center_ms = 0,
    group_ms = 0,
  }
  local triforce_present = false
  local triforce_name = "triforce"
  local music_present = false
  local music_name = "music_studio"
  local control_center_item_name = nil
  local yabai_ready = type(ctx.yabai_available) == "function" and ctx.yabai_available()
  local window_manager_enabled = WINDOW_MANAGER_MODE ~= "disabled"
  local oracle_menu_model = nil
  local music_menu_model = nil
  local control_center_status = nil
  local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)
  local separator_color = theme.OVERLAY1 or theme.SUBTEXT0 or group_border_color
  local code_dir = ctx.CODE_DIR or (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or ((os.getenv("HOME") or "") .. "/src"))

  local function anchor_chip(overrides)
    overrides = overrides or {}
    overrides.height = overrides.height or widget_height
    return ui.anchor_chip_style(ctx, overrides)
  end

  local function anchor_script(script, overrides)
    return ui.anchor_script(script, ctx, overrides)
  end

  local function path_exists(path)
    if not path or path == "" then
      return false
    end
    local file = io.open(path, "r")
    if not file then
      return false
    end
    file:close()
    return true
  end

  local function desk_replacement_items(surface)
    local rows = {
      {
        id = "mission_control",
        label = "Mission Control",
        icon = "󰍹",
        icon_color = tc("SKY"),
        action = "open -a " .. string.format("%q", "Mission Control"),
        order = 10,
      },
      {
        id = "barista_settings",
        label = "Barista Settings",
        icon = "󰒓",
        icon_color = tc("SAPPHIRE"),
        action = ctx.call_script and ctx.call_script(CONFIG_DIR .. "/bin/open_control_panel.sh", "--tab", "home") or "",
        order = 20,
      },
      {
        id = "extension_guide",
        label = "Extension Guide",
        icon = "󰘥",
        icon_color = tc("TEAL"),
        action = "open " .. string.format("%q", CONFIG_DIR .. "/docs/guides/INTERFACE_EXTENSIONS.md"),
        order = 30,
      },
    }
    if surface == "front_app" and path_exists(CONFIG_DIR .. "/scripts/open_keyboard_overlay.sh") then
      table.insert(rows, {
        id = "keyboard_overlay",
        label = "Keyboard Overlay",
        icon = "󰌌",
        icon_color = tc("MAUVE", "LAVENDER"),
        action = ctx.call_script and ctx.call_script(CONFIG_DIR .. "/scripts/open_keyboard_overlay.sh") or "",
        order = 25,
      })
    end
    return rows
  end

  local function extension_rows(surface)
    local rows = desk_replacement_items(surface)
    for _, item in ipairs(interface_extensions.for_surface(CONFIG_DIR, code_dir, state, surface)) do
      table.insert(rows, item)
    end
    table.sort(rows, function(a, b)
      if (a.order or 0) == (b.order or 0) then
        return tostring(a.label or a.id) < tostring(b.label or b.id)
      end
      return (a.order or 0) < (b.order or 0)
    end)
    return rows
  end

  local front_app_extension_items = extension_rows("front_app")
  local control_center_extension_items = extension_rows("control_center")

  -- Front App indicator
  local front_app_start_ms = current_time_ms()
  ui.anchor(layout, {
    ctx = ctx,
    name = "front_app",
    props = {
    position = "left",
    icon = { drawing = true, string = "󰣆", padding_left = 8, padding_right = 8, color = theme.TEXT or theme.WHITE },
    label = { drawing = false },
    script = anchor_script(PLUGIN_DIR .. "/front_app.sh"),
    click_script = popup_toggle_action("front_app"),
    background = anchor_chip(),
    popup = {
      align = "left",
      background = popup_background()
    }
    },
    events = { "front_app_switched" },
    associated_display = associated_displays,
    associated_space = "all",
  })
  table.insert(layout, factory.create_item("front_app_divider", {
    position = "left",
    icon = { drawing = false },
    label = { drawing = true, string = "·", color = separator_color },
    ["label.font"] = font_small,
    ["label.padding_left"] = 4,
    ["label.padding_right"] = 4,
    associated_display = associated_displays,
    associated_space = "all",
    background = { drawing = false },
    updates = false,
  }))

  if oracle_module and type(oracle_module.create_triforce_widget) == "function" then
    local triforce_start_ms = current_time_ms()
    if type(oracle_module.build_menu_model) == "function" then
      oracle_menu_model = oracle_module.build_menu_model(ctx)
    end
    local triforce_widget = oracle_module.create_triforce_widget({
      ctx = ctx,
      model = oracle_menu_model,
      position = "left",
      popup_toggle_script = popup_toggle_action("triforce"),
      popup_background = popup_background(),
      background = anchor_chip(),
      icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
    })

    if triforce_widget then
      triforce_name = triforce_widget.name or "triforce"
      triforce_widget.name = nil
      triforce_widget.script = anchor_script(triforce_widget.script)
      ui.anchor(layout, {
        ctx = ctx,
        name = triforce_name,
        props = triforce_widget,
        hover = false,
        events = { "system_woke" },
        associated_display = associated_displays,
        associated_space = "all",
      })
      table.insert(layout, { action = "exec", cmd = string.format("sleep %.1f; %s --move %s before front_app 2>/dev/null || true", POST_CONFIG_DELAY, SKETCHYBAR_BIN, triforce_name) })
      if triforce_widget.script and triforce_widget.script ~= "" then
        table.insert(layout, {
          action = "exec",
          cmd = string.format("sleep %.1f; NAME=%s %s", POST_CONFIG_DELAY, triforce_name, triforce_widget.script),
        })
      end
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
            popup_item.script = hover_script_cmd
          end
          table.insert(layout, { type = "item", name = item_name, props = popup_item, attach_hover = should_hover })
        end
      end

      triforce_present = true
    end
    metrics.triforce_ms = current_time_ms() - triforce_start_ms
  end

  if music_module and type(music_module.create_widget) == "function" then
    local music_start_ms = current_time_ms()
    if type(music_module.build_menu_model) == "function" then
      music_menu_model = music_module.build_menu_model(ctx)
      if music_menu_model and music_menu_model.ui and music_menu_model.ui.item_name then
        music_name = music_menu_model.ui.item_name
      end
    end
    local music_widget = music_module.create_widget({
      ctx = ctx,
      model = music_menu_model,
      position = "left",
      popup_toggle_script = popup_toggle_action(music_name),
      popup_background = popup_background(),
      background = anchor_chip(),
      icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
    })

    if music_widget then
      music_name = music_widget.name or music_name
      music_widget.name = nil
      music_widget.script = anchor_script(music_widget.script)
      ui.anchor(layout, {
        ctx = ctx,
        name = music_name,
        props = music_widget,
        events = {},
        associated_display = associated_displays,
        associated_space = "all",
      })
      table.insert(layout, {
        action = "exec",
        cmd = string.format(
          "sleep %.1f; if %s --query %s >/dev/null 2>&1; then %s --move %s after %s 2>/dev/null || true; else %s --move %s before front_app 2>/dev/null || true; fi",
          POST_CONFIG_DELAY + 0.2,
          SKETCHYBAR_BIN,
          triforce_name,
          SKETCHYBAR_BIN,
          music_name,
          triforce_name,
          SKETCHYBAR_BIN,
          music_name
        ),
      })
      if type(music_module.create_popup_items) == "function" then
        local popup_ctx = ctx
        if music_menu_model then
          popup_ctx = setmetatable({ music_menu_model = music_menu_model }, { __index = ctx })
        end
        local music_popup_items = music_module.create_popup_items(popup_ctx)
        table.insert(layout, {
          action = "call",
          fn = function()
            if not ctx.sbar or type(ctx.sbar.remove) ~= "function" then
              return
            end
            for _, popup_item in ipairs(music_popup_items or {}) do
              local popup_name = popup_item.name
              if popup_name and popup_name ~= "" then
                pcall(function()
                  ctx.sbar.remove(popup_name)
                end)
              end
            end
          end,
        })
        for _, popup_item in ipairs(music_popup_items or {}) do
          local item_name = popup_item.name
          popup_item.name = nil
          local should_hover = popup_item.hover == true
          popup_item.hover = nil
          if should_hover and not popup_item.script then
            popup_item.script = hover_script_cmd
          end
          table.insert(layout, { type = "item", name = item_name, props = popup_item, attach_hover = should_hover })
        end
      end

      music_present = true
    end
    metrics.music_ms = current_time_ms() - music_start_ms
  end

  -- Front App Popup Items
  local yabai_controls_enabled = window_manager_enabled and yabai_ready and YABAI_CONTROL_SCRIPT and YABAI_CONTROL_SCRIPT ~= ""
  local front_app_style = ui.popup_style(ctx)

  local function add_front_popup_item(item)
    if type(item) ~= "table" then
      return
    end
    local item_name = item.name
    if not item_name or item_name == "" then
      return
    end
    item.name = nil
    local should_hover = item.hover == true
    item.hover = nil
    if should_hover and not item.script then
      item.script = hover_script_cmd
    end
    table.insert(layout, { type = "item", name = item_name, props = item, attach_hover = should_hover })
  end

  local function close_front_app_after(command)
    return ui.close_after("front_app", command, { sketchybar_bin = SKETCHYBAR_BIN })
  end

  local function add_front_header(name, label, color)
    local items = {}
    ui.header(items, "front_app", name, label, {
      style = front_app_style,
      color = color,
      font = font_bold,
      background_drawing = false,
    })
    add_front_popup_item(items[1])
  end

  local function add_front_separator(name)
    local items = {}
    ui.separator(items, "front_app", name, {
      style = front_app_style,
      font = font_small,
      color = "0x40cdd6f4",
    })
    add_front_popup_item(items[1])
  end

  local function add_front_row(name, entry)
    entry = entry or {}
    local items = {}
    ui.row(items, "front_app", name, {
      style = front_app_style,
      icon = { string = entry.icon or "", color = entry.icon_color },
      label = entry.label or "",
      action = entry.action,
      click_script = entry.click_script,
      font = font_small,
      label_color = entry.label_color,
      hover = entry.hover,
      sketchybar_bin = SKETCHYBAR_BIN,
      props = entry.props,
    })
    add_front_popup_item(items[1])
  end

  local function add_front_app_extension_rows(rows)
    if type(rows) ~= "table" or #rows == 0 then
      return
    end
    add_front_separator("front_app.extensions.sep")
    add_front_header("front_app.extensions.header", "Desk", tc("TEAL"))
    for _, row in ipairs(rows) do
      if row.action and row.action ~= "" then
        add_front_row("front_app.extension." .. row.id, {
          icon = row.icon or "󰐕",
          icon_color = row.icon_color or tc("TEAL"),
          label = row.label or row.id,
          click_script = close_front_app_after(row.action),
          label_color = row.label_color,
        })
      end
    end
  end

  add_front_header("front_app.header", "App Controls", tc("SAPPHIRE"))
  add_front_row("front_app.state", {
    icon = "󰆾",
    icon_color = tc("TEAL"),
    label = "Tiled · Normal",
    label_color = tc("SUBTEXT1", "WHITE"),
    hover = false,
  })
  add_front_row("front_app.location", {
    icon = "󰍹",
    icon_color = tc("SKY"),
    label = "Space ? · Display ?",
    label_color = tc("SUBTEXT1", "WHITE"),
    hover = false,
  })
  add_front_separator("front_app.sep0")
  add_front_header("front_app.app_header", "App", tc("PEACH"))

  local app_actions = {
    { name = "front_app.hide", icon = "󰘔", icon_color = tc("PEACH"), label = "Hide App", action = call_script(FRONT_APP_ACTION_SCRIPT, "hide"), shortcut = "⌘H" },
    { name = "front_app.quit", icon = "󰅘", icon_color = tc("RED"), label = "Quit App", action = call_script(FRONT_APP_ACTION_SCRIPT, "quit"), shortcut = "⌘Q" },
    { name = "front_app.force_quit", icon = "󰜏", icon_color = tc("MAROON", "RED"), label = "Force Quit", action = call_script(FRONT_APP_ACTION_SCRIPT, "force-quit") },
  }
  for _, entry in ipairs(app_actions) do
    add_front_row(entry.name, entry)
  end

  add_front_separator("front_app.sep1")
  add_front_header("front_app.window_header", "Window", tc("TEAL"))

  if yabai_controls_enabled then
    local window_actions = {
      { name = "front_app.window.float", icon = "󰒄", icon_color = tc("SAPPHIRE"), label = "Float Window", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-float") },
      { name = "front_app.window.adopt_space_mode", icon = "󰆾", icon_color = tc("TEAL"), label = "Adopt Current Space Mode", action = call_script(YABAI_CONTROL_SCRIPT, "window-adopt-space-mode") },
      { name = "front_app.window.fullscreen", icon = "󰊓", icon_color = tc("GREEN"), label = "Enter Fullscreen", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-fullscreen") },
      { name = "front_app.window.sticky", icon = "󰐊", icon_color = tc("YELLOW"), label = "Toggle Sticky", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-sticky") },
      { name = "front_app.window.topmost", icon = "󰁜", icon_color = tc("MAUVE", "LAVENDER"), label = "Make Topmost", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-topmost") },
      { name = "front_app.window.center", icon = "󰘞", icon_color = tc("BLUE"), label = "Center Window", action = call_script(YABAI_CONTROL_SCRIPT, "window-center") },
    }
    for _, entry in ipairs(window_actions) do
      add_front_row(entry.name, entry)
    end

    add_front_separator("front_app.sep_presets")
    add_front_header("front_app.presets_header", "Presets", tc("YELLOW"))

    local preset_actions = {
      { name = "front_app.preset.utility", icon = "󰉼", icon_color = tc("SAPPHIRE"), label = "Utility", action = call_script(YABAI_CONTROL_SCRIPT, "window-preset-utility") },
      { name = "front_app.preset.focus", icon = "󰓅", icon_color = tc("GREEN"), label = "Focus", action = call_script(YABAI_CONTROL_SCRIPT, "window-preset-focus") },
      { name = "front_app.preset.presentation", icon = "󰊓", icon_color = tc("PEACH"), label = "Presentation", action = call_script(YABAI_CONTROL_SCRIPT, "window-preset-presentation") },
      { name = "front_app.preset.tile_here", icon = "󰆾", icon_color = tc("TEAL"), label = "Tile Here", action = call_script(YABAI_CONTROL_SCRIPT, "window-preset-tile-here") },
    }
    for _, entry in ipairs(preset_actions) do
      add_front_row(entry.name, entry)
    end

    add_front_separator("front_app.sep_defaults")
    add_front_header("front_app.defaults_header", "App Defaults", tc("PEACH"))

    local default_actions = {
      { name = "front_app.default.float", icon = "󰒄", icon_color = tc("PEACH"), label = "Default This App: Float", action = call_script(YABAI_CONTROL_SCRIPT, "app-default-current float") },
      { name = "front_app.default.tile", icon = "󰆾", icon_color = tc("TEAL"), label = "Default This App: Tile", action = call_script(YABAI_CONTROL_SCRIPT, "app-default-current tile") },
      { name = "front_app.default.unset", icon = "󰅖", icon_color = tc("RED"), label = "Unset This App Default", action = call_script(YABAI_CONTROL_SCRIPT, "app-default-current unset") },
    }
    for _, entry in ipairs(default_actions) do
      add_front_row(entry.name, entry)
    end

    add_front_separator("front_app.sep2")
    add_front_header("front_app.move_header", "Move", tc("MAUVE", "LAVENDER"))

    local move_actions = {
      { name = "front_app.move.float_space", icon = "󰒄", icon_color = tc("TEAL"), label = "Send to Float Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-float") },
      { name = "front_app.move.display_prev", icon = "󰍺", icon_color = tc("SKY"), label = "Move to Prev Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-prev") },
      { name = "front_app.move.display_next", icon = "󰍹", icon_color = tc("SKY"), label = "Move to Next Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-next") },
      { name = "front_app.move.space_prev", icon = "󱂬", icon_color = tc("PEACH"), label = "Move to Prev Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-prev-wrap") },
      { name = "front_app.move.space_next", icon = "󱂬", icon_color = tc("PEACH"), label = "Move to Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-next-wrap") },
    }
    for _, entry in ipairs(move_actions) do
      add_front_row(entry.name, entry)
    end
  else
    local unavailable_label = WINDOW_MANAGER_MODE == "disabled"
      and "Window manager disabled for this profile"
      or "Yabai unavailable - run doctor"
    local unavailable_action = (WINDOW_MANAGER_MODE ~= "disabled" and call_script(YABAI_CONTROL_SCRIPT, "doctor", "--fix")) or ""
    add_front_row("front_app.window.unavailable", {
      icon = "󰚌",
      icon_color = tc("YELLOW"),
      label = unavailable_label,
      click_script = close_front_app_after(unavailable_action),
      label_color = tc("SUBTEXT1", "WHITE"),
    })
    add_front_app_extension_rows(front_app_extension_items)
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
      popup_toggle_script = popup_toggle_action(ctx.control_center_item_name or "control_center"),
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
    cc_widget.background = anchor_chip()
    cc_widget.script = anchor_script(cc_widget.script)
    ui.anchor(layout, {
      ctx = ctx,
      name = control_center_item_name,
      props = cc_widget,
      events = { "mouse.entered", "mouse.exited", "space_active_refresh", "space_mode_refresh", "system_woke" },
      associated_display = associated_displays,
      associated_space = "all",
    })

    table.insert(layout, {
      action = "exec",
      cmd = string.format("sleep %.1f; %s --move %s before front_app 2>/dev/null || true",
                          POST_CONFIG_DELAY, SKETCHYBAR_BIN, control_center_item_name)
    })

    local cc_popup_items = control_center_module.create_popup_items(nil, theme, font_string, settings, {
      item_name = control_center_item_name,
      config_dir = CONFIG_DIR,
      scripts_dir = ctx.SCRIPTS_DIR,
      state = state,
      window_manager_mode = WINDOW_MANAGER_MODE,
      window_manager_flags = control_center_status and control_center_status.window_manager or nil,
      extension_items = control_center_extension_items,
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

    metrics.control_center_ms = current_time_ms() - control_center_start_ms

  end

  local group_start_ms = current_time_ms()
  local left_group_children = {}
  if triforce_present then
    table.insert(left_group_children, triforce_name)
  end
  if music_present then
    table.insert(left_group_children, music_name)
  end
  if control_center_item_name then
    table.insert(left_group_children, control_center_item_name)
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
