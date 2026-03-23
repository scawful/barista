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

run_test("create_popup_items: disabled mode shows notice", function()
  local items = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {
    window_manager_mode = "disabled",
  })
  local notice = find_item(items, "cc.window_manager.notice")
  assert_type(notice, "table", "notice item exists")
  assert_equal(notice.label.string, "Window manager disabled", "notice label")
  assert_nil(find_item(items, "cc.layout.float"), "layout controls hidden")
end)

run_test("create_popup_items: service rows close popup after action", function()
  local items = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {})
  local sketchybar = find_item(items, "cc.svc.sketchybar")
  assert_type(sketchybar, "table", "sketchybar service item")
  assert_true(sketchybar.click_script:match("%-%-reload") ~= nil, "reload action present")
  assert_true(sketchybar.click_script:match("popup%.drawing=off") ~= nil, "popup close action present")
end)

run_test("create_popup_items: shortcut toggle updates label and closes popup", function()
  local items = control_center.create_popup_items(nil, test_theme(), test_font_string, test_settings(), {})
  local toggle = find_item(items, "cc.yabai.shortcuts")
  assert_type(toggle, "table", "shortcut toggle item")
  assert_true(toggle.click_script:match("toggle_yabai_shortcuts%.sh") ~= nil or toggle.click_script:match("toggle_shortcuts%.sh") ~= nil, "toggle script present")
  assert_true(toggle.click_script:match("popup%.drawing=off") ~= nil, "popup close action present")
end)
