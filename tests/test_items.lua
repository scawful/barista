-- Unit tests for items_left and items_right declarative layouts

local items_left = require("items_left")
local items_right = require("items_right")
local shell_utils = require("shell_utils")
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
    popup_toggle_action = function(item_name) return "toggle:" .. tostring(item_name) end,
    POST_CONFIG_DELAY = 0.1,
    SPACE_POST_CONFIG_DELAY = 0.0,
    SKETCHYBAR_BIN = "/custom/sketchybar",
    env_prefix = function(values)
      return string.format(
        "BARISTA_SKETCHYBAR_BIN=%s BARISTA_ANCHOR_IDLE_BG=%s ",
        values.BARISTA_SKETCHYBAR_BIN,
        values.BARISTA_ANCHOR_IDLE_BG
      )
    end,
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

  local layout, _, metadata = items_left.get_layout(mock_ctx)
  assert(type(layout) == "table", "layout should be a table")
  assert(#layout > 0, "layout should not be empty")
  assert_type(metadata, "table", "left layout should return runtime metadata")
  assert_equal(#metadata.popup_parents, 0, "disabled optional integrations should not enter the popup registry")
  assert_equal(table.concat(metadata.submenu_parents, "|"), "front_app.more",
    "front-app progressive disclosure should register its nested popup")

  -- Check for front_app
  local found_front_app = false
  local found_front_app_divider = false
  local found_front_app_state = false
  local found_front_app_location = false
  local front_app_hide = nil
  local found_adopt_space_mode = false
  local found_send_float_space = false
  local found_utility_preset = false
  local found_focus_preset = false
  local found_presentation_preset = false
  local found_tile_here_preset = false
  local found_front_app_default_row = false
  local front_app_move_prev = nil
  local front_app_move_next = nil
  local front_app_more = nil
  local front_app_root_rows = 0
  local front_app_more_rows = 0
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.props.position == "popup.front_app" then
      front_app_root_rows = front_app_root_rows + 1
    elseif entry.type == "item" and entry.props.position == "popup.front_app.more" then
      front_app_more_rows = front_app_more_rows + 1
    end
    if entry.type == "item" and entry.name == "front_app" then
      found_front_app = true
      assert(entry.props.position == "left", "front_app should be on the left")
      assert_equal(entry.props.label.drawing, false, "front_app should default to icon-only label state")
      assert_equal(entry.props.background.drawing, true, "front_app should render as a visible chip")
      assert_equal(entry.props.background.color, "0x18313a46", "front_app should use the shared idle chip background")
      assert_true(entry.props.click_script:find(
        "/custom/sketchybar -m --set front_app.more popup.drawing=off --set front_app popup.drawing=toggle",
        1,
        true
      ) ~= nil, "front_app should reset its child and toggle immediately")
      assert_true(entry.props.click_script:find("SENDER=popup_refresh NAME=front_app", 1, true) ~= nil,
        "front_app should refresh popup state asynchronously")
      assert_true(entry.props.click_script:find("/tmp/plugins/front_app.sh", 1, true) ~= nil,
        "front_app popup refresh should use the active plugin path")
      assert_true(entry.props.click_script:find("BARISTA_SKETCHYBAR_BIN=/custom/sketchybar", 1, true) ~= nil,
        "front_app popup refresh should preserve the resolved SketchyBar binary")
      assert_true(entry.props.click_script:find("BARISTA_ANCHOR_IDLE_BG=0x18313a46", 1, true) ~= nil,
        "front_app popup refresh should preserve anchor styling")
      assert_true(entry.props.click_script:find("BARISTA_FRONT_APP_ACTION_ROWS=1", 1, true) ~= nil,
        "front_app popup refresh should include mutable yabai action rows when present")
      assert_true(entry.props.click_script:find("BARISTA_LUA_ONLY=1", 1, true) == nil,
        "compiled front_app popup refresh should not force Lua-only mode")
    elseif entry.type == "item" and entry.name == "front_app_divider" then
      found_front_app_divider = true
      assert_equal(entry.props.label.string, "·", "front_app divider should render a subtle dot separator")
    elseif entry.type == "item" and entry.name == "front_app.state" then
      found_front_app_state = true
    elseif entry.type == "item" and entry.name == "front_app.location" then
      found_front_app_location = true
    elseif entry.type == "item" and entry.name == "front_app.hide" then
      front_app_hide = entry
    elseif entry.type == "item" and entry.name == "front_app.window.adopt_space_mode" then
      found_adopt_space_mode = true
    elseif entry.type == "item" and entry.name == "front_app.move.float_space" then
      found_send_float_space = true
    elseif entry.type == "item" and entry.name == "front_app.preset.utility" then
      found_utility_preset = true
      assert_true(entry.props.click_script:find("yabai_control%.sh window%-preset%-utility") ~= nil, "utility preset should route through yabai_control.sh")
    elseif entry.type == "item" and entry.name == "front_app.preset.focus" then
      found_focus_preset = true
      assert_true(entry.props.click_script:find("yabai_control%.sh window%-preset%-focus") ~= nil, "focus preset should route through yabai_control.sh")
    elseif entry.type == "item" and entry.name == "front_app.preset.presentation" then
      found_presentation_preset = true
      assert_true(entry.props.click_script:find("yabai_control%.sh window%-preset%-presentation") ~= nil, "presentation preset should route through yabai_control.sh")
    elseif entry.type == "item" and entry.name == "front_app.preset.tile_here" then
      found_tile_here_preset = true
      assert_true(entry.props.click_script:find("yabai_control%.sh window%-preset%-tile%-here") ~= nil, "tile-here preset should route through yabai_control.sh")
    elseif entry.type == "item" and type(entry.name) == "string" and entry.name:match("^front_app%.default%.") then
      found_front_app_default_row = true
    elseif entry.type == "item" and entry.name == "front_app.move.display_prev" then
      front_app_move_prev = entry
    elseif entry.type == "item" and entry.name == "front_app.move.display_next" then
      front_app_move_next = entry
    elseif entry.type == "item" and entry.name == "front_app.more" then
      front_app_more = entry
    end
  end
  assert(found_front_app, "front_app item not found in layout")
  assert(found_front_app_divider, "front_app divider not found in layout")
  assert(found_front_app_state, "front_app state row not found in popup layout")
  assert(found_front_app_location, "front_app location row not found in popup layout")
  assert(front_app_hide ~= nil, "front_app hide action not found in popup layout")
  assert(found_adopt_space_mode, "front_app adopt-space-mode action not found in popup layout")
  assert(found_send_float_space, "front_app send-to-float-space action not found in popup layout")
  assert(found_utility_preset, "front_app utility preset not found in popup layout")
  assert(found_focus_preset, "front_app focus preset not found in popup layout")
  assert(found_presentation_preset, "front_app presentation preset not found in popup layout")
  assert(found_tile_here_preset, "front_app tile-here preset not found in popup layout")
  assert_true(not found_front_app_default_row, "front_app should leave persistent app defaults to Control Center")
  assert(front_app_move_prev ~= nil, "front_app move-to-prev-display action not found in popup layout")
  assert(front_app_move_next ~= nil, "front_app move-to-next-display action not found in popup layout")
  assert_equal(front_app_root_rows, 18, "front_app should render only its frequent actions initially")
  assert_equal(front_app_more_rows, 12, "front_app nested popup should retain every preset and move row")
  assert_true(front_app_more ~= nil, "front_app should expose a click-open More Window Actions row")
  assert_equal(front_app_more.props.position, "popup.front_app", "front_app submenu anchor should stay on the root popup")
  assert_equal(front_app_more.props.popup.align, "right", "front_app submenu should open to the right")
  assert_true(front_app_more.props.click_script:find("front_app.more popup.drawing=toggle", 1, true) ~= nil,
    "front_app submenu should use a direct popup toggle")
  assert(front_app_hide.props.click_script:find("popup.drawing=off", 1, true) ~= nil, "front_app actions should close the popup after execution")
  assert(front_app_move_prev.props.click_script:find("yabai_control%.sh window%-display%-prev") ~= nil, "front_app prev-display action should route through yabai_control.sh")
  assert(front_app_move_next.props.click_script:find("yabai_control%.sh window%-display%-next") ~= nil, "front_app next-display action should route through yabai_control.sh")
  assert_true(front_app_move_prev.props.click_script:find("--set front_app.more popup.drawing=off --set front_app popup.drawing=off", 1, true) ~= nil,
    "front_app nested actions should close both popup levels")

  -- Check for effects
  local found_refresh_spaces = false
  local found_deferred_watch = false
  for _, entry in ipairs(layout) do
    if entry.action == "exec" and type(entry.cmd) == "string" and entry.cmd:find("refresh_spaces%.sh") then
      found_refresh_spaces = true
      assert_true(entry.cmd:find("sleep 0%.0;", 1) ~= nil, "refresh_spaces should use the dedicated spaces startup delay")
    elseif entry.action == "post_config_call" and entry.fn == mock_ctx.watch_spaces then
      found_deferred_watch = true
    end
  end
  assert(found_refresh_spaces, "refresh_spaces startup command not found in layout")
  assert(found_deferred_watch, "yabai signal registration should wait until after config commit")

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
    popup_toggle_action = function(item_name) return "toggle:" .. tostring(item_name) end,
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
    lua_only = true,
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

  local layout, _, metadata = items_left.get_layout(mock_ctx)
  local foundUnavailable = false
  local foundDeskHeader = false
  local foundExtensionGuide = false
  local foundMoveAction = false
  local foundLuaOnlyRefresh = false
  local foundPortableActionRows = false
  local foundFrontAppMore = false
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "front_app.window.unavailable" then
      foundUnavailable = true
    end
    if entry.type == "item" and entry.name == "front_app.extensions.header" then
      foundDeskHeader = true
    end
    if entry.type == "item" and entry.name == "front_app.extension.extension_guide" then
      foundExtensionGuide = true
    end
    if entry.type == "item" and entry.name == "front_app.move.display_next" then
      foundMoveAction = true
    end
    if entry.type == "item" and entry.name == "front_app.more" then
      foundFrontAppMore = true
    end
    if entry.type == "item" and entry.name == "front_app"
        and entry.props.click_script:find("/usr/bin/env BARISTA_LUA_ONLY=1", 1, true) ~= nil then
      foundLuaOnlyRefresh = true
    end
    if entry.type == "item" and entry.name == "front_app"
        and entry.props.click_script:find("BARISTA_FRONT_APP_ACTION_ROWS=0", 1, true) ~= nil then
      foundPortableActionRows = true
    end
  end

  assert_true(foundUnavailable, "unavailable yabai row should exist")
  assert_true(foundDeskHeader, "disabled yabai path should expose Desk replacement rows")
  assert_true(foundExtensionGuide, "disabled yabai path should link the extension guide")
  assert_true(not foundMoveAction, "move-window yabai actions should be hidden when yabai is unavailable")
  assert_true(not foundFrontAppMore, "portable front_app should not expose an empty nested popup")
  assert_equal(#metadata.submenu_parents, 0, "portable front_app should not register a missing submenu")
  assert_true(foundLuaOnlyRefresh, "Lua-only front_app popup refresh should keep compiled helpers disabled")
  assert_true(foundPortableActionRows, "portable front_app refresh should omit unavailable yabai action rows")
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
    popup_toggle_action = function(item_name) return "toggle:" .. tostring(item_name) end,
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
        assert_equal(opts.popup_toggle_script, "toggle:status_hub", "control_center should receive the generic direct popup toggle")
        return {
          name = "status_hub",
          script = "/tmp/plugins/control_center.sh",
          click_script = opts.popup_toggle_script,
          popup = { align = "left", background = { drawing = true } },
        }
      end,
      create_popup_items = function(_, _, _, _, opts)
        received_popup_opts = opts
        return {
          { name = "status_hub.action", position = "popup.status_hub", label = { string = "Action" }, hover = true },
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

  local layout, _, metadata = items_left.get_layout(mock_ctx)
  local found_custom_item = false
  local found_custom_subscribe = false
  local found_custom_bracket = false
  local found_custom_popup_action = false

  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "status_hub" then
      found_custom_item = true
    end
    if entry.action == "subscribe_popup_autoclose" and entry.name == "status_hub" then
      found_custom_subscribe = true
    end
    if entry.type == "item" and entry.name == "status_hub.action" then
      found_custom_popup_action = true
      assert_nil(entry.props.hover, "control_center hover metadata should not reach SketchyBar properties")
      assert_equal(entry.props.script, "hover.sh", "control_center hover rows should receive the shared hover script")
      assert_equal(entry.attach_hover, true, "control_center hover rows should attach hover events")
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
  assert_true(found_custom_popup_action, "custom control_center popup action should exist")
  assert_equal(metadata.popup_parents[1], "status_hub", "popup registry should use the created custom control_center name")
  assert_type(received_popup_opts, "table", "popup items should receive opts")
  assert_equal(received_popup_opts.item_name, "status_hub", "popup items should inherit the resolved item name")
  assert_equal(received_popup_opts.config_dir, "/tmp/config", "popup items should receive CONFIG_DIR")
  assert_equal(received_popup_opts.scripts_dir, "/tmp/scripts", "popup items should receive SCRIPTS_DIR")
  print("  items_left custom control_center name test passed!")
end

local function test_items_left_integration_models_and_anchor_order()
  print("Testing items_left integration models and anchor order...")

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
      music = {
        build_menu_model = function()
          return { ui = { item_name = "music_studio" } }
        end,
        create_widget = function()
          return {
            name = "music_studio",
            popup = { align = "left", background = { drawing = true } },
          }
        end,
        create_popup_items = function()
          return {}, { submenu_parents = { "music.studio.more_apps" } }
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

  local layout, _, metadata = items_left.get_layout(mock_ctx)
  assert_type(layout, "table", "layout should be a table")
  assert_equal(oracle_model_calls, 1, "oracle model should be built once per layout pass")
  assert_type(received_widget_model, "table", "oracle widget should receive the shared model")
  assert_equal(received_widget_model, received_popup_model, "oracle popup should reuse the shared model")
  assert_equal(control_center_status_calls, 1, "control_center status should be computed once per layout pass")
  assert_type(received_control_center_widget_status, "table", "control_center widget should receive shared status")
  assert_type(received_control_center_popup_flags, "table", "control_center popup should receive shared flags")
  assert_equal(received_control_center_popup_flags.mode, "required", "control_center popup should reuse window manager flags")
  assert_equal(table.concat(metadata.popup_parents, "|"), "triforce|music_studio|control_center",
    "popup registry should include created optional parents")
  assert_equal(table.concat(metadata.submenu_parents, "|"), "music.studio.more_apps|front_app.more",
    "left layout metadata should expose Music and Front App nested popups")
  local found_triforce_subscription = false
  local found_control_center_subscription = false
  local anchor_order_command = nil
  local anchor_order_count = 0
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
      if entry.cmd:find("--move", 1, true)
        and entry.cmd:find("music_studio", 1, true)
        and entry.cmd:find("control_center", 1, true)
        and entry.cmd:find("front_app", 1, true) then
        anchor_order_count = anchor_order_count + 1
        anchor_order_command = entry.cmd
      end
    end
  end
  assert_true(found_triforce_subscription, "triforce subscription should be present")
  assert_true(found_control_center_subscription, "control_center subscription should be present")
  assert_equal(anchor_order_count, 1, "left anchors should use one deterministic post-config reorder command")
  assert_true(anchor_order_command:find('--move "control_center" before "front_app"', 1, true) ~= nil,
    "control_center should be placed directly before front_app")
  assert_true(anchor_order_command:find('--move "music_studio" before "control_center"', 1, true) ~= nil,
    "music should be placed before control_center")
  assert_true(anchor_order_command:find('--move "triforce" before "music_studio"', 1, true) ~= nil,
    "triforce should be placed before music")
  assert_true(anchor_order_command:match("^sleep%s") == nil,
    "anchor ordering should dispatch immediately after the config commit")

  mock_ctx.integrations.oracle.create_triforce_widget = function()
    return nil
  end
  local _, _, missing_metadata = items_left.get_layout(mock_ctx)
  assert_equal(table.concat(missing_metadata.popup_parents, "|"), "music_studio|control_center",
    "popup registry should omit an enabled integration that did not create a widget")
  print("  items_left integration model/order test passed!")
end

local function test_items_right_layout()
  print("Testing items_right layout...")

  local added_items = {}
  local compiled_calls = {}
  local compiled_fallbacks = {}
  local volume_env_values = nil
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
    CONFIG_DIR = "/tmp/config",
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
    env_prefix = function(t)
      if t.BARISTA_VOLUME_OK ~= nil then
        volume_env_values = t
      end
      return ""
    end,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    compiled_script = function(n, p)
      table.insert(compiled_calls, n)
      compiled_fallbacks[n] = p
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
  assert_true(added_items.system_info.props.script:find("/tmp/plugins/system_info%.sh") ~= nil, "system_info should keep the shell event wrapper")
  assert_true(added_items.system_info.props.update_freq == nil, "system_info timer should be disabled when daemon-managed")
  assert_true(added_items.system_info.props.click_script:find("popup.drawing=toggle", 1, true) ~= nil, "system_info click should toggle immediately")
  assert_true(added_items.system_info.props.click_script:find("popup_refresh", 1, true) ~= nil, "system_info click should refresh popup details asynchronously")
  assert_true(added_items.volume.props.click_script:find("popup.drawing=toggle", 1, true) ~= nil, "volume click should toggle immediately")
  assert_equal(added_items.volume.props.script, "/tmp/plugins/volume.sh", "routine volume events should keep the shell wrapper")
  assert_true(added_items.volume.props.update_freq == nil, "native click refresh should not add a polling timer")
  assert_true(added_items.volume.props.click_script:find("/compiled/volume_popup_helper", 1, true) ~= nil, "volume click should prefer the native popup helper")
  assert_true(added_items.volume.props.click_script:find("popup_refresh || /tmp/plugins/volume.sh popup_refresh", 1, true) ~= nil, "volume click should retain the shell fallback")
  assert_true(added_items.volume.props.click_script:find("volume_click%.sh") == nil, "volume click should not query before toggling through volume_click.sh")
  assert_equal(added_items.battery.props.script, "/tmp/plugins/battery.sh 0xffa6e3a1 0xfff9e2af 0xfff38ba8 0xff89b4fa", "battery should keep the shell event wrapper")
  assert_true(added_items.battery.props.update_freq == nil, "battery timer should be disabled when daemon-managed")
  assert_true(added_items.battery.props.click_script:find("popup.drawing=toggle", 1, true) ~= nil, "battery click should toggle immediately")
  assert_true(added_items.battery.props.click_script:find("popup_refresh", 1, true) ~= nil, "battery click should refresh popup details asynchronously")
  local compiled_summary = table.concat(compiled_calls, ",")
  assert_true(compiled_summary:find("system_info_widget", 1, true) ~= nil, "items_right should resolve the compiled system_info helper")
  assert_true(compiled_summary:find("widget_manager", 1, true) ~= nil, "items_right should resolve the compiled battery helper")
  assert_true(compiled_summary:find("volume_popup_helper", 1, true) ~= nil, "items_right should resolve the compiled volume popup helper")
  assert_equal(compiled_fallbacks.volume_popup_helper, "", "volume native lookup should use an empty resolver fallback")
  assert_type(volume_env_values, "table", "volume helper should receive its runtime environment")
  assert_equal(volume_env_values.BARISTA_CONFIG_DIR, "/tmp/config", "volume helper should receive the config root")
  assert_equal(volume_env_values.BARISTA_RUNTIME_CONTEXT_DIR, "/tmp/config/cache/runtime_context", "volume helper should receive the runtime cache root")
  assert_equal(volume_env_values.BARISTA_VOLUME_POPUP_HELPER, "/compiled/volume_popup_helper", "routine volume updates should share the resolved native helper")
  assert_equal(volume_env_values.BARISTA_VOLUME_OUTPUT_IDLE, "0xffffffff", "volume helper should receive the idle output color")
  assert_equal(volume_env_values.BARISTA_MEDIA_LABEL_MAX, "72", "volume helper should receive the media label cap")

  local volume_state = nil
  local volume_output = nil
  local volume_output_1 = nil
  local volume_media = nil
  local volume_toggle = nil
  local volume_mute = nil
  local volume_startup_refresh = nil
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
    elseif entry.action == "exec" and type(entry.cmd) == "string"
        and entry.cmd:find("--subscribe volume volume_change", 1, true) ~= nil then
      volume_startup_refresh = entry.cmd
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
  assert_true(volume_startup_refresh ~= nil, "volume should subscribe after configuration")
  assert_true(volume_startup_refresh:find("NAME=volume SENDER=routine", 1, true) ~= nil, "volume subscription should perform one ordered native-capable startup refresh")
  assert_true(volume_startup_refresh:find("--trigger volume_change", 1, true) == nil, "volume startup should not race a separate synthetic event")
  assert_true(battery_settings ~= nil, "battery popup should keep the settings shortcut")
  assert_true(battery_settings.props.click_script:find("popup.drawing=off", 1, true) ~= nil, "battery popup actions should close the popup after execution")

  local missing_helper_items = {}
  mock_sbar.add = function(kind, name, props)
    missing_helper_items[name] = { kind = kind, props = props }
  end
  mock_ctx.compiled_script = function(name, fallback)
    if name == "volume_popup_helper" then
      return fallback
    end
    return "/compiled/" .. name
  end
  items_right.get_layout(mock_ctx)
  local portable_volume = missing_helper_items.volume
  assert_true(portable_volume ~= nil, "volume should remain available without compiled helpers")
  assert_equal(portable_volume.props.script, "/tmp/plugins/volume.sh", "helper-missing routine events should remain on the shell wrapper")
  assert_true(portable_volume.props.click_script:find("popup.drawing=toggle", 1, true) ~= nil, "helper-missing click should still toggle immediately")
  assert_true(portable_volume.props.click_script:find("/tmp/plugins/volume.sh popup_refresh", 1, true) ~= nil, "helper-missing click should refresh through the shell path")
  assert_true(portable_volume.props.click_script:find("volume_popup_helper", 1, true) == nil, "helper-missing click should not include a broken native command")
  assert_true(portable_volume.props.click_script:find("||", 1, true) == nil, "helper-missing click should not include an empty fallback chain")

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

local function test_items_right_lmstudio_extension_rows()
  print("Testing items_right LM Studio extension rows...")

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
    theme = { WHITE = "0xffffffff", GREEN = "0xffa6e3a1", YELLOW = "0xfff9e2af", RED = "0xfff38ba8", BLUE = "0xff89b4fa", LAVENDER = "0xffb4befe", TEAL = "0xff94e2d5", bar = { bg = "0xff1e1e2e" } },
    state = {
      appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 },
      widgets = { lmstudio = true },
      machine = { menu_packs = { "personal" } },
      menus = {
        extensions = {
          items = {
            {
              id = "local_model",
              label = "Local Model",
              command = "echo model",
              surface = "lmstudio",
              pack = "personal",
            },
          },
        },
      },
    },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    CONFIG_DIR = "/tmp/config",
    CODE_DIR = "/tmp/code",
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
    icon_for = function(_, d) return d end,
    state_module = { get_icon = function() return "" end },
    env_prefix = function() return "" end,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do table.insert(parts, tostring(arg)) end
      return table.concat(parts, " ")
    end,
    compiled_script = function(_, fallback) return fallback end,
    widget_daemon_enabled = false,
    hover_color = "0x44ffffff",
    hover_animation_curve = "ease_out",
    hover_animation_duration = 10,
  }
  mock_ctx.widget_factory = widgets_module.create_factory(
    { add = function() end, set = function() end },
    mock_ctx.theme,
    mock_ctx.settings,
    mock_ctx.state,
    { widget_height = mock_ctx.widget_height }
  )

  local layout = items_right.get_layout(mock_ctx)
  local found_lmstudio = false
  local found_extension = false
  local found_scawfulbot_default = false
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "lmstudio" then
      found_lmstudio = true
    elseif entry.type == "item" and entry.name == "lmstudio.extension.local_model" then
      found_extension = true
    elseif entry.type == "item" and entry.props and entry.props.label == "scawfulbot MLX" then
      found_scawfulbot_default = true
    end
  end
  assert_true(found_lmstudio, "lmstudio should render when explicitly enabled")
  assert_true(found_extension, "lmstudio extension row should render")
  assert_true(not found_scawfulbot_default, "personal model rows should not be hardcoded by default")
  print("  items_right LM Studio extension test passed!")
end

local function test_items_right_task_focus_surface()
  print("Testing items_right Task Pulse surface...")

  local function build_layout(widgets, task_sources, task_provider, meeting_cache_file, capture_section, capture_state, meeting_cache_max_age_seconds)
    local state = {
      appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 },
      widgets = widgets or {},
      menus = {
        calendar = {
          task_sources = task_sources,
          task_provider = task_provider,
          meeting_cache_file = meeting_cache_file,
          meeting_cache_max_age_seconds = meeting_cache_max_age_seconds,
          capture_section = capture_section,
          capture_state = capture_state,
        },
      },
    }
    local mock_ctx = {
      settings = {
        font = {
          text = "Inter",
          numbers = "JetBrains Mono",
          icon = "Symbols Nerd Font",
          style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
          sizes = { small = 12, text = 14, icon = 16, numbers = 14 },
        },
      },
      theme = {
        WHITE = "0xffffffff",
        DARK_WHITE = "0xffbac2de",
        GREEN = "0xffa6e3a1",
        YELLOW = "0xfff9e2af",
        RED = "0xfff38ba8",
        BLUE = "0xff89b4fa",
        SKY = "0xff89dceb",
        LAVENDER = "0xffb4befe",
        BG_SEC_COLR = "0x18313a46",
        bar = { bg = "0xff1e1e2e" },
      },
      state = state,
      font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
      CONFIG_DIR = "/tmp/config",
      CODE_DIR = "/tmp/code",
      PLUGIN_DIR = "/tmp/plugins",
      SCRIPTS_DIR = "/tmp/scripts",
      widget_corner_radius = 6,
      widget_height = 22,
      popup_background = function() return { drawing = true } end,
      hover_script_cmd = "hover.sh",
      POST_CONFIG_DELAY = 0.1,
      SKETCHYBAR_BIN = "sketchybar",
      group_bg_color = "0x44000000",
      group_border_color = "0xffffffff",
      group_border_width = 1,
      group_corner_radius = 4,
      icon_for = function(_, fallback) return fallback end,
      state_module = { get_icon = function() return "" end },
      env_prefix = shell_utils.env_prefix,
      call_script = shell_utils.call_script,
      compiled_script = function(_, fallback) return fallback end,
      widget_daemon_enabled = false,
      hover_color = "0x44ffffff",
      hover_border_color = "0xffffffff",
      hover_border_width = 1,
      hover_animation_curve = "ease_out",
      hover_animation_duration = 10,
    }
    mock_ctx.widget_factory = widgets_module.create_factory(
      { add = function() end, set = function() end },
      mock_ctx.theme,
      mock_ctx.settings,
      state,
      {
        widget_height = mock_ctx.widget_height,
        widget_corner_radius = mock_ctx.widget_corner_radius,
      }
    )
    return items_right.get_layout(mock_ctx)
  end

  local function find_entry(layout, name)
    for _, entry in ipairs(layout) do
      if entry.name == name then
        return entry
      end
    end
    return nil
  end

  local default_layout = build_layout({}, { "/tmp/tasks.md" }, "files")
  assert_true(find_entry(default_layout, "task_focus") == nil, "Task Pulse should remain absent by default")

  local empty_layout = build_layout({ task_focus = true }, { "", "   " }, "files")
  assert_true(find_entry(empty_layout, "task_focus") == nil, "Task Pulse should stay absent without a non-empty source")

  local sources = {
    "/tmp/tasks board.md",
    "/tmp/tasks;touch should-not-run.org",
  }
  local provider = "files;touch should-not-run"
  local layout = build_layout(
    { task_focus = true },
    sources,
    provider,
    "/tmp/events cache.tsv",
    "Inbox $(touch should-not-run)",
    "NEXT`touch should-not-run`",
    7200
  )
  local task_focus = find_entry(layout, "task_focus")
  assert_true(task_focus ~= nil, "Task Pulse should render when explicitly enabled with task sources")
  assert_equal(task_focus.props.label.string, "Tasks", "Task Pulse should start with a compact Tasks label")
  assert_equal(task_focus.props.drawing, true, "Task Pulse should draw when enabled")

  local expected_env = shell_utils.env_prefix({
    BARISTA_CALENDAR_TASK_SOURCES = table.concat(sources, ":"),
    BARISTA_CAPTURE_SECTION = "Inbox $(touch should-not-run)",
    BARISTA_CAPTURE_STATE = "NEXT`touch should-not-run`",
    BARISTA_TASK_PROVIDER = provider,
  })
  assert_equal(task_focus.props.script:sub(1, #expected_env), expected_env, "Task Pulse should safely prefix provider and source environment")
  assert_true(task_focus.props.script:find("/tmp/plugins/task_pulse%.sh") ~= nil, "Task Pulse events should run the pulse plugin")
  assert_true(task_focus.props.click_script:find("popup%.drawing=toggle") ~= nil, "Task Pulse click should open its own popup immediately")
  assert_true(task_focus.props.click_script:find("task_pulse%.sh") ~= nil, "Task Pulse click should refresh popup data")
  assert_true(task_focus.props.click_script:match("&%s*$") ~= nil, "Task Pulse click refresh should be asynchronous")

  local expected_rows = {
    "task_focus.summary",
    "task_focus.focus",
    "task_focus.next",
    "task_focus.waiting",
    "task_focus.blocked",
    "task_focus.capture",
    "task_focus.open",
    "task_focus.timer",
  }
  local row_count = 0
  for _, name in ipairs(expected_rows) do
    local row = find_entry(layout, name)
    assert_true(row ~= nil, name .. " should be present in the capped Task Pulse popup")
    row_count = row_count + 1
  end
  local actual_row_count = 0
  for _, entry in ipairs(layout) do
    if entry.type == "item" and type(entry.name) == "string" and entry.name:match("^task_focus%.") then
      actual_row_count = actual_row_count + 1
    end
  end
  assert_equal(actual_row_count, row_count, "Task Pulse popup should contain only its eight static rows")
  assert_true(find_entry(layout, "task_focus.complete") == nil,
    "non-syshelp providers should not expose Complete Focus")

  local capture = find_entry(layout, "task_focus.capture")
  local open_board = find_entry(layout, "task_focus.open")
  local timer = find_entry(layout, "task_focus.timer")
  assert_true(capture.props.click_script:find("/tmp/config/scripts/task_capture%.sh") ~= nil, "Capture Task should use Barista's task_capture.sh")
  assert_true(capture.props.click_script:find("BARISTA_CAPTURE_SECTION='Inbox $(touch should-not-run)'", 1, true) ~= nil,
    "Capture Task should pass the configured capture section literally")
  assert_true(capture.props.click_script:find("BARISTA_CAPTURE_STATE='NEXT`touch should-not-run`'", 1, true) ~= nil,
    "Capture Task should pass the configured capture state literally")
  assert_true(open_board.props.click_script:find("/tmp/config/scripts/task_action%.sh") ~= nil, "Open Board should use Barista's task_action.sh")
  assert_true(open_board.props.click_script:find("open", 1, true) ~= nil, "Open Board should request the open action")
  assert_true(timer.props.click_script:find("/tmp/config/scripts/focus_session%.py") ~= nil, "Focus timer should use the local session engine")
  assert_true(timer.props.click_script:find("bash '/tmp/config/scripts/focus_session.py'", 1, true) == nil,
    "Focus timer should execute its Python shebang instead of passing it to Bash")
  assert_true(timer.props.click_script:find("toggle", 1, true) ~= nil, "Focus timer should toggle one menu-only session")
  assert_true(timer.props.click_script:find("task_state_changed", 1, true) ~= nil, "Focus timer should refresh Task Pulse after changes")

  local syshelp_layout = build_layout({ task_focus = true }, { "/tmp/tasks.md" }, "syshelp")
  local complete_focus = find_entry(syshelp_layout, "task_focus.complete")
  assert_true(complete_focus ~= nil, "syshelp Task Pulse should expose Complete Focus")
  assert_equal(complete_focus.props.label, "Complete Focus…", "Complete Focus should signal confirmation")
  assert_true(complete_focus.props.click_script:find("/tmp/config/scripts/task_action%.sh") ~= nil,
    "Complete Focus should use Barista's task_action.sh")
  assert_true(complete_focus.props.click_script:find("complete%-focus") ~= nil,
    "Complete Focus should request the provider-gated action")

  local subscribed = false
  local popup_autoclose = false
  local hover_attached = false
  local grouped = false
  for _, entry in ipairs(layout) do
    if entry.action == "exec" and type(entry.cmd) == "string"
      and entry.cmd:find("--subscribe task_focus task_state_changed system_woke", 1, true) ~= nil then
      subscribed = true
    elseif entry.action == "subscribe_popup_autoclose" and entry.name == "task_focus" then
      popup_autoclose = true
    elseif entry.action == "attach_hover" and entry.name == "task_focus" then
      hover_attached = true
    elseif entry.type == "bracket" and entry.name == "right_group_1" then
      for _, child in ipairs(entry.children or {}) do
        if child == "task_focus" then
          grouped = true
        end
      end
    end
  end
  assert_true(subscribed, "Task Pulse should subscribe to task changes and wake events")
  assert_true(popup_autoclose, "Task Pulse should register popup autoclose")
  assert_true(hover_attached, "Task Pulse should register hover feedback")
  assert_true(grouped, "Task Pulse should join the right-side clock group")

  local calendar_header = find_entry(layout, "clock.calendar.header")
  assert_true(calendar_header ~= nil, "calendar header should remain present")
  assert_true(calendar_header.props.update_freq == nil, "calendar popup should not poll while closed")
  assert_true(calendar_header.props.script:find("BARISTA_CALENDAR_MEETING_CACHE=", 1, true) ~= nil, "calendar should pass the opt-in meeting cache path")
  assert_true(calendar_header.props.script:find("BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS='7200'", 1, true) ~= nil,
    "calendar should pass the configured meeting cache freshness limit")
  local meeting = find_entry(layout, "clock.calendar.meeting.next")
  assert_true(meeting ~= nil, "calendar should own one cached meeting row")
  assert_equal(meeting.props.icon, "󰃰", "cached meeting should keep its calendar glyph in the icon field")
  assert_equal(meeting.props["icon.drawing"], true, "cached meeting icon should draw with the row")
  assert_true(meeting.props["icon.font"]:find("Symbols Nerd Font:", 1, true) == 1,
    "cached meeting icon should use the configured icon font")
  assert_true(meeting.props["label.font"]:find("Inter:", 1, true) == 1,
    "cached meeting label should use the text font rather than the numbers font")
  assert_true(find_entry(layout, "clock.calendar.tasks.waiting") ~= nil, "calendar should expose a distinct waiting row")

  print("  items_right Task Pulse surface test passed!")
end

test_items_left_layout()
test_items_left_without_yabai()
test_items_left_control_center_custom_name()
test_items_left_integration_models_and_anchor_order()
test_items_right_layout()
test_items_right_lmstudio_extension_rows()
test_items_right_task_focus_surface()

print("\nAll item layout tests passed!")
