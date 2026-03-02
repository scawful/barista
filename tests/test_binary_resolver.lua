-- test_binary_resolver.lua - Tests for modules/binary_resolver.lua

local binary_resolver = require("binary_resolver")

-- normalize_window_manager_mode tests
run_test("normalize_wm_mode: nil → auto", function()
  assert_equal(binary_resolver.normalize_window_manager_mode(nil), "auto")
end)

run_test("normalize_wm_mode: empty → auto", function()
  assert_equal(binary_resolver.normalize_window_manager_mode(""), "auto")
end)

run_test("normalize_wm_mode: off → disabled", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("off"), "disabled")
end)

run_test("normalize_wm_mode: false → disabled", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("false"), "disabled")
end)

run_test("normalize_wm_mode: disable → disabled", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("disable"), "disabled")
end)

run_test("normalize_wm_mode: optional → optional", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("optional"), "optional")
end)

run_test("normalize_wm_mode: opt → optional", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("opt"), "optional")
end)

run_test("normalize_wm_mode: required → required", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("required"), "required")
end)

run_test("normalize_wm_mode: enable → required", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("enable"), "required")
end)

run_test("normalize_wm_mode: ON (case insensitive) → required", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("ON"), "required")
end)

run_test("normalize_wm_mode: unknown passes through", function()
  assert_equal(binary_resolver.normalize_window_manager_mode("custom"), "custom")
end)

-- compute_window_manager_enabled tests
run_test("compute_wm_enabled: disabled mode → false", function()
  assert_true(not binary_resolver.compute_window_manager_enabled("disabled", "/usr/bin/yabai"))
end)

run_test("compute_wm_enabled: required + yabai present → true", function()
  assert_true(binary_resolver.compute_window_manager_enabled("required", "/usr/bin/yabai"))
end)

run_test("compute_wm_enabled: required + no yabai → false", function()
  assert_true(not binary_resolver.compute_window_manager_enabled("required", nil))
end)

run_test("compute_wm_enabled: required + empty yabai → false", function()
  assert_true(not binary_resolver.compute_window_manager_enabled("required", ""))
end)

run_test("compute_wm_enabled: auto + yabai present → true", function()
  assert_true(binary_resolver.compute_window_manager_enabled("auto", "/usr/bin/yabai"))
end)

run_test("compute_wm_enabled: auto + no yabai → false", function()
  assert_true(not binary_resolver.compute_window_manager_enabled("auto", nil))
end)

-- compiled_script tests
run_test("compiled_script: lua_only returns fallback", function()
  local result = binary_resolver.compiled_script("/nonexistent", true, "popup_hover", "/fallback.sh")
  assert_equal(result, "/fallback.sh", "lua-only fallback")
end)

run_test("compiled_script: missing binary returns fallback", function()
  local result = binary_resolver.compiled_script("/nonexistent", false, "nonexistent_binary", "/fallback.sh")
  assert_equal(result, "/fallback.sh", "missing binary fallback")
end)
