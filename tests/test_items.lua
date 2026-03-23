-- Unit tests for items_left and items_right declarative layouts

local items_left = require("items_left")
local items_right = require("items_right")
local widgets_module = require("widgets")

local function test_items_left_layout()
  print("Testing items_left layout...")
  
  -- Mock context
  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16 }
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
    SKETCHYBAR_BIN = "sketchybar",
    associated_displays = "all",
    FRONT_APP_ACTION_SCRIPT = "front_app_action.sh",
    YABAI_CONTROL_SCRIPT = "yabai_control.sh",
    call_script = function(s, a) return s .. " " .. a end,
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
  mock_ctx.widget_factory = widgets_module.create_factory(mock_ctx.theme, mock_ctx.settings, mock_ctx.state)

  local layout = items_left.get_layout(mock_ctx)
  assert(type(layout) == "table", "layout should be a table")
  assert(#layout > 0, "layout should not be empty")

  -- Check for front_app
  local found_front_app = false
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "front_app" then
      found_front_app = true
      assert(entry.props.position == "left", "front_app should be on the left")
    end
  end
  assert(found_front_app, "front_app item not found in layout")

  -- Check for effects
  local found_init_spaces = false
  for _, entry in ipairs(layout) do
    if entry.action == "call" and entry.fn == mock_ctx.init_spaces then
      found_init_spaces = true
    end
  end
  assert(found_init_spaces, "init_spaces call not found in layout")

  print("  items_left layout test passed!")
end

local function test_items_right_layout()
  print("Testing items_right layout...")

  -- Mock context
  local mock_ctx = {
    settings = {
      font = {
        text = "Inter",
        numbers = "Inter",
        icon = "Symbols Nerd Font",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12, text = 14, icon = 16 }
      }
    },
    theme = { WHITE = "0xffffffff", GREEN = "0xffa6e3a1", YELLOW = "0xfff9e2af", RED = "0xfff38ba8", BLUE = "0xff89b4fa", LAVENDER = "0xffb4befe", bar = { bg = "0xff1e1e2e" } },
    state = { appearance = { widget_scale = 1.0, bar_height = 28, corner_radius = 6 }, widgets = {} },
    font_string = function(f, s, sz) return string.format("%s:%s:%0.1f", f, s, sz) end,
    PLUGIN_DIR = "/tmp/plugins",
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
    compiled_script = function(n, p) return p end,
    hover_color = "0x44ffffff",
    hover_animation_curve = "ease_out",
    hover_animation_duration = 10,
  }
  mock_ctx.widget_factory = widgets_module.create_factory(mock_ctx.theme, mock_ctx.settings, mock_ctx.state)

  local layout = items_right.get_layout(mock_ctx)
  assert(type(layout) == "table", "layout should be a table")
  assert(#layout > 0, "layout should not be empty")

  -- Check for clock
  local found_clock = false
  for _, entry in ipairs(layout) do
    if entry.type == "item" and entry.name == "clock" then
      found_clock = true
      assert(entry.props.position == "right", "clock should be on the right")
    end
  end
  assert(found_clock, "clock item not found in layout")

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
test_items_right_layout()

print("\nAll item layout tests passed!")
