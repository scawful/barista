-- Unit tests for items_left and items_right declarative layouts

local items_left = require("items_left")
local items_right = require("items_right")
local widgets_module = require("widgets")

local function test_items_left_layout()
  print("Testing items_left layout...")

  local mock_sbar = {
    add = function() end,
    set = function() end,
  }
  
  -- Mock context
  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
      }
    },
    theme = { WHITE = "0xffffffff", SAPPHIRE = "0xff74c7ec", SKY = "0xff89dceb", PEACH = "0xfffab387", RED = "0xfff38ba8", MAROON = "0xffeba0ac", TEAL = "0xff94e2d5", YELLOW = "0xfff9e2af", MAUVE = "0xffcba6f7", LAVENDER = "0xffb4befe", bar = { bg = "0xff1e1e2e" } },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
    widget_corner_radius = 6,
    widget_height = 22,
    popup_background = function() return { drawing = true } end,
    hover_script_cmd = "hover.sh",
    popup_toggle_action = function() return "toggle.sh" end,
    POST_CONFIG_DELAY = 0.1,
    SPACE_POST_CONFIG_DELAY = 0.0,
    SKETCHYBAR_BIN = "sketchybar",
    associated_displays = "all",
    FRONT_APP_ACTION_SCRIPT = "front_app_action.sh",
    YABAI_CONTROL_SCRIPT = "yabai_control.sh",
    call_script = function(s, ...)
      local parts = { s }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, arg)
      end
      return table.concat(parts, " ")
    end,
    CONFIG_DIR = "/tmp/config",
    control_center_module = nil, -- Test without for now
    WINDOW_MANAGER_MODE = "optional",
    group_bg_color = "0x44000000",
    group_border_color = "0xffffffff",
    group_border_width = 1,
    group_corner_radius = 4,
    init_spaces = function() end,
    refresh_spaces = function() end,
    watch_spaces = function() end,
    yabai_available = function() return true end,
  }
  mock_ctx.widget_factory = widgets_module.create_factory(
    mock_sbar,
    mock_ctx.theme,
    mock_ctx.settings,
    mock_ctx.state,
    {
      widget_height = mock_ctx.widget_height,
      widget_corner_radius = mock_ctx.widget_corner_radius,
    }
  )

  local layout = items_left.get_layout(mock_ctx)
  assert(type(layout) == "table", "layout should be a table")
  assert(#layout > 0, "layout should not be empty")

  -- Check for front_app
  local found_front_app = false
  local found_front_app_state = false
  local found_front_app_location = false
  local front_app_hide = nil
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "front_app" then
      found_front_app = true
      assert(entry.props.position == "left", "front_app should be on the left")
    elseif entry.type == "item" and entry.name == "front_app.state" then
      found_front_app_state = true
    elseif entry.type == "item" and entry.name == "front_app.location" then
      found_front_app_location = true
    elseif entry.type == "item" and entry.name == "front_app.hide" then
      front_app_hide = entry
    end
  end
  assert(found_front_app, "front_app item not found in layout")
  assert(found_front_app_state, "front_app state row not found in popup layout")
  assert(found_front_app_location, "front_app location row not found in popup layout")
  assert(front_app_hide ~= nil, "front_app hide action not found in popup layout")
  assert(front_app_hide.props.click_script:find("popup.drawing=off", 1, true) ~= nil, "front_app actions should close the popup after execution")

  -- Check for effects
  local found_refresh_spaces = false
  for _, entry in ipairs(layout) do
    if entry.action == "exec" and type(entry.cmd) == "string" and entry.cmd:find("refresh_spaces%.sh") then
      found_refresh_spaces = true
      assert_true(entry.cmd:find("sleep 0%.0;", 1) ~= nil, "refresh_spaces should use the dedicated spaces startup delay")
    end
  end
  assert(found_refresh_spaces, "refresh_spaces startup command not found in layout")

  print("  items_left layout test passed!")
end

local function test_items_left_without_yabai()
  print("Testing items_left layout without yabai...")

  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
      }
    },
    theme = { WHITE = "0xffffffff", YELLOW = "0xfff9e2af", TEAL = "0xff94e2d5", SAPPHIRE = "0xff74c7ec", SKY = "0xff89dceb", PEACH = "0xfffab387", RED = "0xfff38ba8", MAROON = "0xffeba0ac", MAUVE = "0xffcba6f7", LAVENDER = "0xffb4befe", BLUE = "0xff89b4fa", bar = { bg = "0xff1e1e2e" } },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
    widget_corner_radius = 6,
    widget_height = 22,
    popup_background = function() return { drawing = true } end,
    hover_script_cmd = "hover.sh",
    popup_toggle_action = function() return "toggle.sh" end,
    POST_CONFIG_DELAY = 0.1,
    SKETCHYBAR_BIN = "sketchybar",
    associated_displays = "all",
    FRONT_APP_ACTION_SCRIPT = "front_app_action.sh",
    YABAI_CONTROL_SCRIPT = "yabai_control.sh",
    call_script = function(s, ...)
      local parts = { s }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, arg)
      end
      return table.concat(parts, " ")
    end,
    CONFIG_DIR = "/tmp/config",
    control_center_module = nil,
    WINDOW_MANAGER_MODE = "optional",
    group_bg_color = "0x44000000",
    group_border_color = "0xffffffff",
    group_border_width = 1,
    group_corner_radius = 4,
    refresh_spaces = function() end,
    watch_spaces = function() end,
    yabai_available = function() return false end,
    init_spaces = function() end,
    widget_factory = widgets_module.create_factory(
      { add = function() end, set = function() end },
      { WHITE = "0xffffffff", YELLOW = "0xfff9e2af", bar = { bg = "0xff1e1e2e" } },
      {
        font = {
          text = "Inter",
          numbers = "Inter",
          icon = "Symbols Nerd Font",
          style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
          sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
        }
      },
      { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
      { widget_height = 22, widget_corner_radius = 6 }
    ),
  }

  local layout = items_left.get_layout(mock_ctx)
  local foundUnavailable = false
  local foundMoveAction = false
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "front_app.window.unavailable" then
      foundUnavailable = true
    end
    if entry.type == "item" and entry.name == "front_app.move.display_next" then
      foundMoveAction = true
    end
  end

  assert_true(foundUnavailable, "unavailable yabai row should exist")
  assert_true(not foundMoveAction, "move-window yabai actions should be hidden when yabai is unavailable")
  print("  items_left no-yabai test passed!")
end

local function test_items_left_control_center_custom_name()
  print("Testing items_left layout with custom control_center name...")

  local received_popup_opts = nil
  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
      }
    },
    theme = {
      WHITE = "0xffffffff",
      SAPPHIRE = "0xff74c7ec",
      SKY = "0xff89dceb",
      PEACH = "0xfffab387",
      RED = "0xfff38ba8",
      MAROON = "0xffeba0ac",
      TEAL = "0xff94e2d5",
      YELLOW = "0xfff9e2af",
      MAUVE = "0xffcba6f7",
      LAVENDER = "0xffb4befe",
      bar = { bg = "0xff1e1e2e" }
    },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
    widget_corner_radius = 6,
    widget_height = 22,
    popup_background = function() return { drawing = true } end,
    hover_script_cmd = "hover.sh",
    popup_toggle_action = function() return "toggle.sh" end,
    POST_CONFIG_DELAY = 0.1,
    SKETCHYBAR_BIN = "sketchybar",
    associated_displays = "all",
    FRONT_APP_ACTION_SCRIPT = "front_app_action.sh",
    YABAI_CONTROL_SCRIPT = "yabai_control.sh",
    call_script = function(s, ...)
      local parts = { s }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, arg)
      end
      return table.concat(parts, " ")
    end,
    CONFIG_DIR = "/tmp/config",
    SCRIPTS_DIR = "/tmp/scripts",
    control_center_item_name = "status_hub",
    control_center_module = {
      create_widget = function(opts)
        assert_equal(opts.item_name, "status_hub", "items_left should pass the resolved control_center item name")
        return {
          name = "status_hub",
          script = "/tmp/plugins/control_center.sh",
          popup = { align = "left", background = { drawing = true } },
        }
      end,
      create_popup_items = function(_, _, _, _, opts)
        received_popup_opts = opts
        return {
          { name = "status_hub.header", position = "popup.status_hub", label = { string = "Header" } },
        }
      end,
    },
    WINDOW_MANAGER_MODE = "optional",
    group_bg_color = "0x44000000",
    group_border_color = "0xffffffff",
    group_border_width = 1,
    group_corner_radius = 4,
    init_spaces = function() end,
    refresh_spaces = function() end,
    watch_spaces = function() end,
    yabai_available = function() return true end,
  }
  mock_ctx.widget_factory = widgets_module.create_factory(
    { add = function() end, set = function() end },
    mock_ctx.theme,
    mock_ctx.settings,
    mock_ctx.state,
    {
      widget_height = mock_ctx.widget_height,
      widget_corner_radius = mock_ctx.widget_corner_radius,
    }
  )

  local layout = items_left.get_layout(mock_ctx)
  local found_custom_item = false
  local found_custom_subscribe = false
  local found_custom_bracket = false

  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "status_hub" then
      found_custom_item = true
    end
    if entry.action == "subscribe_popup_autoclose" and entry.name == "status_hub" then
      found_custom_subscribe = true
    end
    if entry.type == "bracket" and entry.name == "left_group" then
      for _, child in ipairs(entry.children or {}) do
        if child == "status_hub" then
          found_custom_bracket = true
        end
        assert_true(child ~= "control_center", "left_group should not fall back to the legacy hardcoded name")
      end
    end
  end

  assert_true(found_custom_item, "custom control_center item should exist")
  assert_true(found_custom_subscribe, "custom control_center item should be subscribed by name")
  assert_true(found_custom_bracket, "left_group should include custom control_center item name")
  assert_type(received_popup_opts, "table", "popup items should receive opts")
  assert_equal(received_popup_opts.item_name, "status_hub", "popup items should inherit the resolved item name")
  assert_equal(received_popup_opts.config_dir, "/tmp/config", "popup items should receive CONFIG_DIR")
  assert_equal(received_popup_opts.scripts_dir, "/tmp/scripts", "popup items should receive SCRIPTS_DIR")
  print("  items_left custom control_center name test passed!")
end

local function test_items_left_reuses_oracle_and_control_center_status()
  print("Testing items_left layout reuses oracle and control_center model state...")

  local oracle_model_calls = 0
  local control_center_status_calls = 0
  local received_widget_model = nil
  local received_popup_model = nil
  local received_control_center_widget_status = nil
  local received_control_center_popup_flags = nil

  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
      }
    },
    theme = {
      WHITE = "0xffffffff",
      SAPPHIRE = "0xff74c7ec",
      SKY = "0xff89dceb",
      PEACH = "0xfffab387",
      RED = "0xfff38ba8",
      MAROON = "0xffeba0ac",
      TEAL = "0xff94e2d5",
      YELLOW = "0xfff9e2af",
      MAUVE = "0xffcba6f7",
      LAVENDER = "0xffb4befe",
      BLUE = "0xff89b4fa",
      GREEN = "0xffa6e3a1",
      bar = { bg = "0xff1e1e2e" }
    },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
    SCRIPTS_DIR = "/tmp/scripts",
    widget_corner_radius = 6,
    widget_height = 22,
    popup_background = function() return { drawing = true } end,
    hover_script_cmd = "hover.sh",
    triforce_hover_script_cmd = "hover.sh",
    popup_toggle_action = function() return "toggle.sh" end,
    POST_CONFIG_DELAY = 0.1,
    SPACE_POST_CONFIG_DELAY = 0.0,
    SKETCHYBAR_BIN = "sketchybar",
    associated_displays = "all",
    FRONT_APP_ACTION_SCRIPT = "front_app_action.sh",
    YABAI_CONTROL_SCRIPT = "yabai_control.sh",
    call_script = function(s, ...)
      local parts = { s }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, arg)
      end
      return table.concat(parts, " ")
    end,
    CONFIG_DIR = "/tmp/config",
    WINDOW_MANAGER_MODE = "optional",
    group_bg_color = "0x44000000",
    group_border_color = "0xffffffff",
    group_border_width = 1,
    group_corner_radius = 4,
    refresh_spaces = function() end,
    watch_spaces = function() end,
    yabai_available = function() return true end,
    sbar = { remove = function() end },
    integrations = {
      oracle = {
        build_menu_model = function(ctx)
          oracle_model_calls = oracle_model_calls + 1
          return {
            title = "Oracle Hub",
            state = {
              repo_ok = true,
              widget_icon = "󰯙",
              widget_label = "Oracle",
              show_label = true,
              update_freq = 30,
              alerts_level = "ok",
              triforce_widget = "/tmp/oos-triforce-widget",
            },
            sections = {
              {
                id = "play",
                label = "Oracle Session",
                color = "0xffa6e3a1",
                presentation = "direct",
                entries = {
                  { id = "continue", icon = "󰐃", label = "Continue: Test", action = "continue.sh", prominent = true },
                },
              },
            },
          }
        end,
        create_triforce_widget = function(opts)
          received_widget_model = opts.model
          return {
            name = "triforce",
            popup = { align = "left", background = { drawing = true } },
          }
        end,
        create_triforce_popup_items = function(ctx)
          received_popup_model = ctx.oracle_menu_model
          return {
            { name = "oracle.triforce.header", position = "popup.triforce", label = { string = "Oracle Hub" } },
          }
        end,
      },
    },
    control_center_item_name = "control_center",
    control_center_module = {
      get_status = function()
        control_center_status_calls = control_center_status_calls + 1
        return {
          layout = "bsp",
          window_manager = {
            mode = "required",
            enabled = true,
            required = true,
            has_yabai = true,
            has_skhd = true,
            yabai_running = true,
            skhd_running = true,
          },
        }
      end,
      create_widget = function(opts)
        received_control_center_widget_status = opts.status
        return {
          name = "control_center",
          popup = { align = "left", background = { drawing = true } },
        }
      end,
      create_popup_items = function(_, _, _, _, opts)
        received_control_center_popup_flags = opts.window_manager_flags
        return {
          { name = "control_center.header", position = "popup.control_center", label = { string = "Control Center" } },
        }
      end,
    },
  }
  mock_ctx.widget_factory = widgets_module.create_factory(
    { add = function() end, set = function() end },
    mock_ctx.theme,
    mock_ctx.settings,
    mock_ctx.state,
    {
      widget_height = mock_ctx.widget_height,
      widget_corner_radius = mock_ctx.widget_corner_radius,
    }
  )

  local layout = items_left.get_layout(mock_ctx)
  assert_type(layout, "table", "layout should be a table")
  assert_equal(oracle_model_calls, 1, "oracle model should be built once per layout pass")
  assert_type(received_widget_model, "table", "oracle widget should receive the shared model")
  assert_equal(received_widget_model, received_popup_model, "oracle popup should reuse the shared model")
  assert_equal(control_center_status_calls, 1, "control_center status should be computed once per layout pass")
  assert_type(received_control_center_widget_status, "table", "control_center widget should receive shared status")
  assert_type(received_control_center_popup_flags, "table", "control_center popup should receive shared flags")
  assert_equal(received_control_center_popup_flags.mode, "required", "control_center popup should reuse window manager flags")
  local found_triforce_subscription = false
  local found_control_center_subscription = false
  for _, entry in ipairs(layout) do
    if entry.action == "exec" and type(entry.cmd) == "string" then
      if entry.cmd:find("--subscribe triforce system_woke", 1, true) ~= nil then
        found_triforce_subscription = true
        assert_true(entry.cmd:find("space_change", 1, true) == nil, "triforce should not subscribe to the legacy active-space event")
        assert_true(entry.cmd:find("space_mode_refresh", 1, true) == nil, "triforce should not subscribe to space_mode_refresh")
      elseif entry.cmd:find("--subscribe control_center", 1, true) ~= nil then
        found_control_center_subscription = true
        assert_true(entry.cmd:find("space_active_refresh", 1, true) ~= nil, "control_center should subscribe to the dedicated active-space event")
        assert_true(entry.cmd:find(" space_change", 1, true) == nil, "control_center should not subscribe to the legacy space_change event")
      end
    end
  end
  assert_true(found_triforce_subscription, "triforce subscription should be present")
  assert_true(found_control_center_subscription, "control_center subscription should be present")
  print("  items_left shared model/state test passed!")
end

local function test_items_right_layout()
  print("Testing items_right layout...")

  local added_items = {}
  local compiled_calls = {}
  local mock_sbar = {
    add = function(kind, name, props)
      added_items[name] = { kind = kind, props = props }
    end,
    set = function() end,
  }

  -- Mock context
  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16, numbers = 14 }
      }
    },
    theme = { WHITE = "0xffffffff", GREEN = "0xffa6e3a1", YELLOW = "0xfff9e2af", RED = "0xfff38ba8", BLUE = "0xff89b4fa", LAVENDER = "0xffb4befe", bar = { bg = "0xff1e1e2e" } },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
    SCRIPTS_DIR = "/tmp/scripts",
    widget_height = 22,
    popup_background = function() return { drawing = true } end,
    hover_script_cmd = "hover.sh",
    popup_toggle_action = function() return "toggle.sh" end,
    POST_CONFIG_DELAY = 0.1,
    SKETCHYBAR_BIN = "sketchybar",
    group_bg_color = "0x44000000",
    group_border_color = "0xffffffff",
    group_border_width = 1,
    group_corner_radius = 4,
    icon_for = function(k, d) return d end,
    state_module = { get_icon = function() return "icon" end },
    env_prefix = function(t) return "" end,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    compiled_script = function(n, p)
      table.insert(compiled_calls, n)
      return "/compiled/" .. n
    end,
    widget_daemon_enabled = true,
    hover_color = "0x44ffffff",
    hover_animation_curve = "ease_out",
    hover_animation_duration = 10,
  }
  mock_ctx.widget_factory = widgets_module.create_factory(
    mock_sbar,
    mock_ctx.theme,
    mock_ctx.settings,
    mock_ctx.state,
    {
      widget_height = mock_ctx.widget_height,
    }
  )

  local layout = items_right.get_layout(mock_ctx)
  assert(type(layout) == "table", "layout should be a table")
  assert(#layout > 0, "layout should not be empty")

  -- Check for clock
  assert(added_items.clock ~= nil, "clock item not registered via widget factory")
  assert(added_items.clock.props.position == "right", "clock should be on the right")
  assert_equal(added_items.clock.props.script, "/compiled/clock_widget", "clock should prefer compiled helper")
  assert_true(added_items.clock.props.update_freq == nil, "clock timer should be disabled when daemon-managed")
  assert_equal(added_items.system_info.props.script, "/tmp/plugins/system_info.sh", "system_info should keep the shell event wrapper")
  assert_true(added_items.system_info.props.update_freq == nil, "system_info timer should be disabled when daemon-managed")
  assert_true(added_items.system_info.props.click_script:find("popup_refresh", 1, true) ~= nil, "system_info click should refresh popup details")
  assert_true(added_items.volume.props.click_script:find("volume_click%.sh") ~= nil, "volume click should route through the dedicated click handler")
  assert_equal(added_items.battery.props.script, "/tmp/plugins/battery.sh '0xffa6e3a1' '0xfff9e2af' '0xfff38ba8' '0xff89b4fa'", "battery should keep the shell event wrapper")
  assert_true(added_items.battery.props.update_freq == nil, "battery timer should be disabled when daemon-managed")
  assert_true(added_items.battery.props.click_script:find("popup_refresh", 1, true) ~= nil, "battery click should refresh popup details")
  local compiled_summary = table.concat(compiled_calls, ",")
  assert_true(compiled_summary:find("system_info_widget", 1, true) ~= nil, "items_right should resolve the compiled system_info helper")
  assert_true(compiled_summary:find("widget_manager", 1, true) ~= nil, "items_right should resolve the compiled battery helper")

  local volume_state = nil
  local volume_output = nil
  local volume_output_1 = nil
  local volume_media = nil
  local volume_toggle = nil
  local volume_mute = nil
  local battery_settings = nil
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "volume.state" then
      volume_state = entry
    elseif entry.type == "item" and entry.name == "volume.output" then
      volume_output = entry
    elseif entry.type == "item" and entry.name == "volume.output.1" then
      volume_output_1 = entry
    elseif entry.type == "item" and entry.name == "volume.media" then
      volume_media = entry
    elseif entry.type == "item" and entry.name == "volume.transport.toggle" then
      volume_toggle = entry
    elseif entry.type == "item" and entry.name == "volume.mute" then
      volume_mute = entry
    elseif entry.type == "item" and entry.name == "battery.settings" then
      battery_settings = entry
    end
  end
  assert_true(volume_state ~= nil, "volume popup should expose the current audio state row")
  assert_true(volume_output ~= nil, "volume popup should expose the output device row")
  assert_true(volume_output_1 ~= nil, "volume popup should expose switchable output rows")
  assert_true(volume_output_1.props.click_script:find("media_control%.sh set%-output 1") ~= nil, "volume output switch rows should target the media helper")
  assert_true(volume_media ~= nil, "volume popup should expose now-playing state")
  assert_true(volume_toggle ~= nil, "volume popup should expose play/pause control")
  assert_true(volume_toggle.props.click_script:find("media_control%.sh playpause") ~= nil, "volume transport toggle should use the media helper")
  assert_true(volume_mute ~= nil, "volume popup should keep a mute toggle")
  assert_true(volume_mute.props.click_script:find("popup.drawing=off", 1, true) ~= nil, "volume popup actions should close the popup after execution")
  assert_true(battery_settings ~= nil, "battery popup should keep the settings shortcut")
  assert_true(battery_settings.props.click_script:find("popup.drawing=off", 1, true) ~= nil, "battery popup actions should close the popup after execution")

  -- Check for bracket
  local found_bracket = false
  for _, entry in ipairs(layout) do
    if entry.type == "bracket" and (entry.name == "right_group_1" or entry.name == "right_group_2") then
      found_bracket = true
    end
  end
  assert(found_bracket, "bracket not found in layout")

  print("  items_right layout test passed!")
end

test_items_left_layout()
test_items_left_without_yabai()
test_items_left_control_center_custom_name()
test_items_left_reuses_oracle_and_control_center_status()
test_items_right_layout()

print("\nAll item layout tests passed!")
