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

run_test("shortcuts.get_command: reload uses serialized reload helper", function()
  local command = shortcuts.get_command("reload_sketchybar")
  assert_type(command, "string", "reload command")
  assert_true(command:match("plugins/reload_sketchybar%.sh") ~= nil, "reload should use serialized helper")
  assert_true(command:match("sketchybar %-%-reload") == nil, "reload shortcut should not call raw sketchybar --reload")
end)

run_test("shortcuts.get_command: open_terminal prefers Ghostty-style launch", function()
  local command = shortcuts.get_command("open_terminal")
  assert_type(command, "string", "open_terminal command")
  assert_true(command ~= "", "open_terminal command should not be empty")
  assert_true(
    command:match("Ghostty") ~= nil or command:match("open %-a Terminal") ~= nil,
    "open_terminal should prefer Ghostty and fall back to Terminal"
  )
  if command:match("Ghostty") ~= nil then
    assert_true(command:match("mkdir") ~= nil, "Ghostty terminal launch should be debounced")
    assert_true(command:match("bash %-lc '") ~= nil, "Ghostty terminal launch should pass a literal bash payload")
    assert_true(command:match("%$lock_dir") ~= nil, "Ghostty terminal launch should preserve lock_dir for bash")
  end
end)

run_test("shortcuts.get: launch_z3ed is exposed when z3ed is available", function()
  local command = shortcuts.get_command("launch_z3ed")
  if command == "" then
    print("    ⊘ launch_z3ed unavailable in this environment")
    assert_true(true, "skipped — z3ed not resolved")
    return
  end

  local shortcut = shortcuts.get("launch_z3ed")
  assert_true(shortcut ~= nil, "launch_z3ed shortcut should be listed")
  assert_equal(shortcut.symbol, "⌘⌥Z", "launch_z3ed symbol")
  assert_true(
    command:match("Ghostty") ~= nil or command:match("Terminal") ~= nil,
    "launch_z3ed should launch through Ghostty or Terminal fallback"
  )
  assert_true(command:match("z3ed") ~= nil, "launch_z3ed should invoke z3ed")
  if command:match("Ghostty") ~= nil then
    assert_true(command:match("mkdir") ~= nil, "launch_z3ed should be debounced")
    assert_true(command:match("bash %-lc '") ~= nil, "launch_z3ed should pass a literal bash payload")
    assert_true(command:match("%$lock_dir") ~= nil, "launch_z3ed should preserve lock_dir for bash")
  end
end)
