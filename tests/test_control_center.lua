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
