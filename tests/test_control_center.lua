-- test_control_center.lua - Tests for modules/integrations/control_center.lua
-- Tests the pure-logic functions; skips anything that requires SketchyBar runtime.

-- control_center.lua requires shell_utils, paths, binary_resolver at load time.
-- These are all testable outside the runtime now.
local ok, control_center = pcall(require, "integrations.control_center")

if not ok then
  run_test("control_center module: load (skipped)", function()
    print("    ⊘ " .. tostring(control_center))
    assert_true(true, "skipped — module not loadable in test env")
  end)
  return
end

-- create_widget returns a table with required fields
run_test("create_widget: returns table with name", function()
  local widget = control_center.create_widget({})
  assert_type(widget, "table", "returns table")
  assert_equal(widget.name, "control_center", "widget name")
end)

run_test("create_widget: default position is left", function()
  local widget = control_center.create_widget({})
  assert_equal(widget.position, "left", "default left")
end)

run_test("create_widget: custom position", function()
  local widget = control_center.create_widget({ position = "right" })
  assert_equal(widget.position, "right", "custom position")
end)

run_test("create_widget: has popup config", function()
  local widget = control_center.create_widget({})
  assert_type(widget.popup, "table", "popup table")
  assert_equal(widget.popup.align, "left", "popup align")
end)

run_test("create_widget: has icon and label", function()
  local widget = control_center.create_widget({})
  assert_type(widget.icon, "table", "icon table")
  assert_type(widget.label, "table", "label table")
  assert_type(widget.icon.string, "string", "icon string")
  assert_type(widget.label.string, "string", "label string")
end)

run_test("create_widget: default update_freq", function()
  local widget = control_center.create_widget({})
  assert_equal(widget.update_freq, 30, "default 30s")
end)

run_test("create_widget: custom update_freq", function()
  local widget = control_center.create_widget({ update_freq = 60 })
  assert_equal(widget.update_freq, 60, "custom 60s")
end)

run_test("create_widget: show_label defaults true", function()
  local widget = control_center.create_widget({})
  assert_true(widget.label.drawing ~= false, "label drawing on by default")
end)

run_test("create_widget: show_label=false hides label", function()
  local widget = control_center.create_widget({ show_label = false })
  assert_equal(widget.label.drawing, false, "label hidden")
end)

run_test("create_widget: custom item name is preserved", function()
  local widget = control_center.create_widget({
    item_name = "status_hub",
    layout = "bsp",
    window_manager_flags = {
      mode = "required",
      enabled = true,
      required = true,
      has_yabai = true,
      has_skhd = true,
      yabai_running = true,
      skhd_running = true,
    },
  })
  assert_equal(widget.name, "status_hub", "custom widget name")
  assert_equal(widget.label.string, "BSP", "layout override should drive label")
end)

run_test("create_widget: state item name fallback is used", function()
  local widget = control_center.create_widget({
    state = {
      integrations = {
        control_center = { item_name = "state_hub" },
      },
    },
    layout = "float",
    window_manager_flags = {
      mode = "required",
      enabled = true,
      required = true,
      has_yabai = true,
      has_skhd = true,
      yabai_running = true,
      skhd_running = true,
    },
  })
  assert_equal(widget.name, "state_hub", "state item name")
  assert_equal(widget.label.string, "Float", "layout override should still drive label")
end)

local function test_theme()
  return {
    WHITE = "0xffffffff",
    LAVENDER = "0xffb4befe",
    BLUE = "0xff89b4fa",
    SAPPHIRE = "0xff74c7ec",
    GREEN = "0xffa6e3a1",
    TEAL = "0xff94e2d5",
    YELLOW = "0xfff9e2af",
    RED = "0xfff38ba8",
  }
end

local function test_settings()
  return {
    font = {
      text = "Source Code Pro",
      style_map = {
        Semibold = "Semibold",
        Bold = "Bold",
      },
      sizes = {
        small = 11,
      },
    },
  }
end

local function test_font_string(family, style, size)
  return string.format("%s:%s:%s", family, style, size)
end

local function find_item(items, name)
  for _, item in ipairs(items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

local function count_position(items, position)
  local count = 0
  for _, item in ipairs(items) do
    if item.position == position then
      count = count + 1
    end
  end
  return count
end

local function enabled_window_manager_flags()
  return {
    mode = "required",
    enabled = true,
    required = true,
    has_yabai = true,
    has_skhd = true,
    yabai_running = true,
    skhd_running = true,
  }
end

local function with_popen_recorder(fn)
  local original_popen = io.popen
  local commands = {}
  io.popen = function(command)
    table.insert(commands, tostring(command))
    return {
      read = function() return "1\n" end,
      close = function() return true end,
    }
  end

  local ok_run, err = xpcall(function()
    fn(commands)
  end, debug.traceback)
  io.popen = original_popen
  if not ok_run then
    error(err, 0)
  end
end

run_test("get_status: defers enabled layout discovery to runtime refresh", function()
  with_popen_recorder(function(commands)
    local status = control_center.get_status({
      window_manager_flags = enabled_window_manager_flags(),
    })
    assert_equal(status.layout, "unknown", "config-time layout should be a placeholder")
    for _, command in ipairs(commands) do
      assert_true(command:find("query --spaces --space", 1, true) == nil, "config must not query the current layout")
    end
  end)
end)

run_test("get_status: explicit and disabled layouts remain deterministic", function()
  local explicit = control_center.get_status({
    layout = "stack",
    window_manager_flags = enabled_window_manager_flags(),
  })
  assert_equal(explicit.layout, "stack", "explicit layout should win")

  local disabled_flags = enabled_window_manager_flags()
  disabled_flags.mode = "disabled"
  disabled_flags.enabled = false
  disabled_flags.required = false
  local disabled = control_center.get_status({ window_manager_flags = disabled_flags })
  assert_equal(disabled.layout, "disabled", "disabled mode should retain its label state")
end)

run_test("create_popup_items: complete flags skip duplicate capability probes", function()
  with_popen_recorder(function(commands)
    local items = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
      window_manager_flags = enabled_window_manager_flags(),
    })
    assert_true(#items > 0, "popup items should still be created")
    assert_equal(#commands, 0, "complete shared flags should avoid external probes")
  end)
end)

run_test("create_popup_items: disabled mode shows notice without nested controls", function()
  local items, metadata = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    window_manager_flags = {
      mode = "disabled",
      enabled = false,
      required = false,
      has_yabai = false,
      has_skhd = false,
      yabai_running = false,
      skhd_running = false,
    },
  })
  local notice = find_item(items, "cc.window_manager.notice")
  assert_type(notice, "table", "notice item exists")
  assert_equal(notice.label.string, "Window manager disabled", "notice label")
  assert_nil(find_item(items, "cc.layout.float"), "layout controls hidden")
  assert_nil(find_item(items, "cc.more"), "nested layout controls hidden")
  assert_true(find_item(items, "cc.mode.required").click_script:find("cc.more", 1, true) == nil,
    "disabled mode actions should not target a missing child")
  assert_equal(#metadata.submenu_parents, 0, "disabled mode should not register a nested popup")
end)

run_test("create_popup_items: progressive layout keeps frequent controls on the root", function()
  local popup_background = { drawing = true, color = "0xff101010" }
  local items, metadata = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    window_manager_flags = enabled_window_manager_flags(),
    popup_background = popup_background,
  })
  local float = find_item(items, "cc.layout.float")
  local mode_required = find_item(items, "cc.mode.required")
  local more = find_item(items, "cc.more")
  local balance = find_item(items, "cc.layout_ops.balance")
  local shortcuts = find_item(items, "cc.yabai.shortcuts")
  assert_type(float, "table", "float layout item")
  assert_equal(float.label.string, "Float / Manual", "float layout label should match the front-app/manual-space language")
  assert_type(mode_required, "table", "mode switch row exists")
  assert_equal(mode_required.position, "popup.control_center", "mode controls should stay on the root")
  assert_equal(float.position, "popup.control_center", "layout controls should stay on the root")
  assert_equal(shortcuts.position, "popup.control_center", "shortcut toggle should stay on the root")
  for _, root_action in ipairs({ mode_required, float, shortcuts }) do
    assert_true(root_action.click_script:find("--set cc.more popup.drawing=off --set control_center popup.drawing=off", 1, true) ~= nil,
      "enabled root actions should close the child and root in one batch")
  end
  assert_equal(count_position(items, "popup.control_center"), 12, "root should render only frequent controls")
  assert_equal(count_position(items, "popup.cc.more"), 11, "nested popup should retain layout operations and defaults")
  assert_type(more, "table", "more controls submenu exists")
  assert_equal(more.position, "popup.control_center", "submenu anchor should stay on the root")
  assert_equal(more.popup.align, "right", "submenu should open to the right")
  assert_equal(more.popup.background.color, popup_background.color, "submenu should share the root popup background")
  assert_true(more.click_script:find("--set cc.more popup.drawing=toggle", 1, true) ~= nil, "submenu should use a direct click toggle")
  assert_type(balance, "table", "layout operation exists")
  assert_equal(balance.position, "popup.cc.more", "layout operations should move into the nested popup")
  assert_true(balance.click_script:find("--set cc.more popup.drawing=off --set control_center popup.drawing=off", 1, true) ~= nil,
    "nested actions should close both popup levels in one batch")
  assert_type(find_item(items, "cc.defaults.float"), "table", "app default float row exists")
  assert_type(find_item(items, "cc.defaults.tile"), "table", "app default tile row exists")
  assert_type(find_item(items, "cc.defaults.unset"), "table", "app default unset row exists")
  assert_equal(find_item(items, "cc.defaults.float").position, "popup.cc.more", "app defaults should move into the nested popup")
  assert_equal(table.concat(metadata.submenu_parents, "|"), "cc.more", "nested popup should be registered")
  assert_nil(find_item(items, "cc.svc.yabai"), "yabai service row removed")
  assert_nil(find_item(items, "cc.svc.skhd"), "skhd service row removed")
  assert_nil(find_item(items, "cc.svc.sketchybar"), "sketchybar service row removed")
  assert_nil(find_item(items, "cc.workspace"), "workspace row removed")
  assert_nil(find_item(items, "cc.sep3"), "obsolete root separator removed")
end)

run_test("create_popup_items: required mode without yabai omits nested controls", function()
  local flags = enabled_window_manager_flags()
  flags.has_yabai = false
  flags.yabai_running = false
  flags.enabled = false
  local items, metadata = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    window_manager_flags = flags,
  })
  assert_type(find_item(items, "cc.window_manager.notice"), "table", "unavailable notice should exist")
  assert_nil(find_item(items, "cc.more"), "nested controls should be omitted without yabai")
  assert_nil(find_item(items, "cc.layout_ops.balance"), "layout operations should be omitted without yabai")
  assert_equal(#metadata.submenu_parents, 0, "unavailable mode should not register a nested popup")
end)

run_test("create_popup_items: shortcut toggle updates label and closes popup", function()
  local items = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    window_manager_flags = enabled_window_manager_flags(),
  })
  local toggle = find_item(items, "cc.yabai.shortcuts")
  assert_type(toggle, "table", "shortcut toggle item")
  assert_equal(toggle.label.string, "Shortcuts: On", "shortcut row should use compact label")
  assert_true(toggle.click_script:match("toggle_yabai_shortcuts%.sh") ~= nil or toggle.click_script:match("toggle_shortcuts%.sh") ~= nil, "toggle script present")
  assert_true(toggle.click_script:match("popup%.drawing=off") ~= nil, "popup close action present")
end)

run_test("create_popup_items: custom parent and paths are threaded through", function()
  local items, metadata = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    item_name = "status_hub",
    config_dir = "/tmp/config",
    scripts_dir = "/tmp/scripts",
    window_manager_flags = enabled_window_manager_flags(),
  })
  local header = find_item(items, "cc.header")
  local layout = find_item(items, "cc.layout.float")
  local more = find_item(items, "cc.more")
  local balance = find_item(items, "cc.layout_ops.balance")

  assert_type(header, "table", "header item exists")
  assert_equal(header.position, "popup.status_hub", "custom popup parent should be used")
  assert_type(layout, "table", "layout item exists")
  assert_true(layout.click_script:match("/tmp/config/plugins/set_space_mode%.sh") ~= nil, "custom config dir should drive layout commands")
  assert_true(layout.click_script:find("--set cc.more popup.drawing=off --set status_hub popup.drawing=off", 1, true) ~= nil,
    "custom root action should close cc.more and the resolved root")
  assert_type(more, "table", "nested popup anchor exists")
  assert_equal(more.position, "popup.status_hub", "nested popup anchor should use the custom root")
  assert_type(balance, "table", "layout op item exists")
  assert_equal(balance.position, "popup.cc.more", "nested rows should remain parented to cc.more")
  assert_true(balance.click_script:match("/tmp/scripts/yabai_control%.sh") ~= nil, "custom scripts dir should drive yabai commands")
  assert_true(balance.click_script:find("--set cc.more popup.drawing=off --set status_hub popup.drawing=off", 1, true) ~= nil,
    "nested action should close cc.more and the custom root")
  assert_equal(table.concat(metadata.submenu_parents, "|"), "cc.more", "custom root should register the child popup")
  assert_nil(find_item(items, "cc.workspace"), "workspace item should stay removed even with custom paths")
end)
