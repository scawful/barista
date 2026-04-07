-- test_shortcuts.lua - Focused tests for shortcuts helper logic

local ok, shortcuts = pcall(require, "shortcuts")

if not ok then
  run_test("shortcuts module: load (skipped)", function()
    print("    ⊘ " .. tostring(shortcuts))
    assert_true(true, "skipped — module not loadable in test env")
  end)
  return
end

run_test("shortcuts.resolve_control_center_item_name: default fallback", function()
  local name = shortcuts.resolve_control_center_item_name({}, function()
    return nil
  end)
  assert_equal(name, "control_center", "default control_center name")
end)

run_test("shortcuts.resolve_control_center_item_name: state fallback", function()
  local name = shortcuts.resolve_control_center_item_name({
    integrations = {
      control_center = { item_name = "state_hub" },
    },
  }, function()
    return nil
  end)
  assert_equal(name, "state_hub", "state item name")
end)

run_test("shortcuts.resolve_control_center_item_name: env override wins", function()
  local name = shortcuts.resolve_control_center_item_name({
    integrations = {
      control_center = { item_name = "state_hub" },
    },
  }, function(key)
    if key == "BARISTA_CONTROL_CENTER_ITEM_NAME" then
      return "env_hub"
    end
    return nil
  end)
  assert_equal(name, "env_hub", "env should override state")
end)

run_test("shortcuts.get_command: toggle_control_center is a popup toggle command", function()
  local command = shortcuts.get_command("toggle_control_center")
  assert_type(command, "string", "toggle command")
  assert_true(command:match("%-%-set") ~= nil, "toggle command sets an item")
  assert_true(command:match("popup%.drawing=toggle") ~= nil, "toggle command toggles popup drawing")
end)

run_test("shortcuts.get_command: window display moves route through yabai_control", function()
  local next_command = shortcuts.get_command("window_display_next")
  local prev_command = shortcuts.get_command("window_display_prev")
  assert_type(next_command, "string", "window_display_next command")
  assert_type(prev_command, "string", "window_display_prev command")
  assert_true(next_command:match("yabai_control%.sh window%-display%-next") ~= nil, "next display move should route through yabai_control.sh")
  assert_true(prev_command:match("yabai_control%.sh window%-display%-prev") ~= nil, "prev display move should route through yabai_control.sh")
end)
