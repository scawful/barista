-- test_paths.lua - Tests for modules/paths.lua

local paths = require("paths")

run_test("expand_path: tilde expansion", function()
  local home = os.getenv("HOME")
  local result = paths.expand_path("~/foo/bar")
  assert_equal(result, home .. "/foo/bar", "tilde expansion")
end)

run_test("expand_path: absolute path unchanged", function()
  local result = paths.expand_path("/usr/local/bin")
  assert_equal(result, "/usr/local/bin", "absolute unchanged")
end)

run_test("expand_path: nil returns nil", function()
  assert_nil(paths.expand_path(nil), "nil input")
end)

run_test("expand_path: empty returns nil", function()
  assert_nil(paths.expand_path(""), "empty input")
end)

run_test("expand_path: non-string returns nil", function()
  assert_nil(paths.expand_path(42), "number input")
end)

run_test("resolve_code_dir: default fallback", function()
  -- With nil state and no env override, should fall back to $HOME/src
  local saved = os.getenv("BARISTA_CODE_DIR")
  -- Can't unset env in Lua, so we test with nil state
  local result = paths.resolve_code_dir(nil)
  assert_type(result, "string", "returns string")
  assert_true(#result > 0, "non-empty result")
end)

run_test("resolve_code_dir: reads state.paths.code_dir", function()
  local state = { paths = { code_dir = "/custom/code" } }
  local result = paths.resolve_code_dir(state)
  assert_equal(result, "/custom/code", "state override")
end)

run_test("build_paths_table: has expected keys", function()
  local t = paths.build_paths_table("/config", "/code", nil)
  assert_equal(t.config_dir, "/config", "config_dir")
  assert_equal(t.code_dir, "/code", "code_dir")
  assert_type(t.menu_data, "string", "menu_data")
  assert_type(t.yaze, "string", "yaze")
  assert_type(t.afs, "string", "afs")
  assert_type(t.readme, "string", "readme")
end)

run_test("build_paths_table: profile paths overlay", function()
  local t = paths.build_paths_table("/config", "/code", { custom_key = "/custom/path" })
  assert_equal(t.custom_key, "/custom/path", "profile overlay")
  assert_equal(t.config_dir, "/config", "base preserved")
end)

run_test("build_scripts_table: has expected keys", function()
  local t = paths.build_scripts_table("/config", "/scripts", "/plugins")
  assert_type(t.yabai_control, "string", "yabai_control")
  assert_type(t.set_appearance, "string", "set_appearance")
  assert_type(t.halext_menu, "string", "halext_menu")
end)
