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

run_test("shortcuts.get_command: task focus uses the compact calendar surface", function()
  local shortcut = shortcuts.get("open_task_focus")
  local command = shortcuts.get_command("open_task_focus")
  assert_true(shortcut ~= nil, "open_task_focus shortcut should be listed")
  assert_equal(shortcut.symbol, "⌘⌥D", "open_task_focus symbol")
  assert_type(command, "string", "task focus command")
  assert_true(command:match("scripts/task_focus%.sh") ~= nil, "task focus should use task_focus.sh")
end)

run_test("shortcuts AFS Studio action: manifest-backed launcher wins", function()
  local command = shortcuts._build_afs_studio_action({
    apps_launcher = "/tmp/code/tools/afs/launch.sh",
    apps_launcher_ok = true,
    studio_launcher = "/tmp/code/lab/afs-scawful/scripts/afs/utils/afs-studio",
    studio_launcher_ok = true,
  })
  assert_true(command:match("/lab/afs/apps/studio") == nil, "AFS Studio must not target retired apps/studio")
  assert_true(command:match("tools/afs/launch%.sh.*launch afs_studio") ~= nil, "AFS Studio should use the manifest launcher")
end)

run_test("shortcuts AFS Studio action: missing launcher fallback stays hidden", function()
  local command = shortcuts._build_afs_studio_action({
    studio_launcher = "/tmp/code/lab/afs-scawful/scripts/afs/utils/afs-studio",
    studio_launcher_ok = false,
  })
  assert_equal(command, "", "unresolved launcher fallback must not become an action")
end)

run_test("shortcuts.get_command: missing AFS Labeler has no synthetic build action", function()
  local command = shortcuts.get_command("launch_afs_labeler")
  assert_type(command, "string", "AFS Labeler command")
  assert_true(command:match("/lab/afs/apps/studio") == nil, "Labeler must not target retired apps/studio")
  assert_true(command:match("cmake %-%-build") == nil, "missing Labeler should not synthesize a build command")
end)

run_test("shortcuts.list_declared: documentation catalog is machine-independent", function()
  local declared = shortcuts.list_declared()
  assert_equal(#declared, #shortcuts.global, "declared catalog should include every global shortcut")
  local found_z3ed = false
  for _, shortcut in ipairs(declared) do
    if shortcut.action == "launch_z3ed" then
      found_z3ed = true
      assert_equal(shortcut.requires, "z3ed", "declared shortcut should retain availability metadata")
    end
  end
  assert_true(found_z3ed, "declared catalog should retain conditional shortcuts")
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
