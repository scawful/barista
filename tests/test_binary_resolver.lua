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

-- normalize_runtime_backend tests
run_test("normalize_runtime_backend: nil -> auto", function()
  assert_equal(binary_resolver.normalize_runtime_backend(nil), "auto")
end)

run_test("normalize_runtime_backend: empty -> auto", function()
  assert_equal(binary_resolver.normalize_runtime_backend(""), "auto")
end)

run_test("normalize_runtime_backend: lua-only -> lua", function()
  assert_equal(binary_resolver.normalize_runtime_backend("lua-only"), "lua")
end)

run_test("normalize_runtime_backend: compiled -> compiled", function()
  assert_equal(binary_resolver.normalize_runtime_backend("compiled"), "compiled")
end)

run_test("normalize_runtime_backend: unknown -> auto", function()
  assert_equal(binary_resolver.normalize_runtime_backend("weird"), "auto")
end)

run_test("resolve_runtime_backend: env override wins", function()
  local result = binary_resolver.resolve_runtime_backend(
    { modes = { runtime_backend = "auto" } },
    function(name)
      if name == "BARISTA_RUNTIME_BACKEND" then
        return "lua"
      end
      return nil
    end
  )
  assert_equal(result, "lua")
end)

run_test("resolve_runtime_backend: legacy lua env still works", function()
  local result = binary_resolver.resolve_runtime_backend(
    "auto",
    function(name)
      if name == "BARISTA_LUA_ONLY" then
        return "1"
      end
      return nil
    end
  )
  assert_equal(result, "lua")
end)

run_test("resolve_runtime_backend: state backend used when env missing", function()
  local result = binary_resolver.resolve_runtime_backend({ modes = { runtime_backend = "lua" } }, function()
    return nil
  end)
  assert_equal(result, "lua")
end)

run_test("read_runtime_backend_from_state: reads state file", function()
  local tmpdir = os.tmpname() .. "_barista_binary_resolver"
  os.execute(string.format("mkdir -p %q", tmpdir))
  local state_path = tmpdir .. "/state.json"
  local file = assert(io.open(state_path, "w"))
  file:write('{"modes":{"runtime_backend":"lua"}}')
  file:close()

  local result = binary_resolver.read_runtime_backend_from_state(tmpdir)
  assert_equal(result, "lua")

  os.remove(state_path)
  os.execute(string.format("rmdir %q", tmpdir))
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

run_test("compiled_script: old popup manager does not intercept popup switch upgrade", function()
  local tmpdir = os.tmpname() .. "_barista_popup_switch_upgrade"
  local bin_dir = tmpdir .. "/bin"
  os.execute(string.format("mkdir -p %q", bin_dir))

  local old_manager = assert(io.open(bin_dir .. "/popup_manager", "w"))
  old_manager:write("old event-only manager")
  old_manager:close()

  local result = binary_resolver.compiled_script(
    tmpdir,
    false,
    "popup_switch",
    tmpdir .. "/plugins/popup_manager.sh"
  )
  assert_equal(
    result,
    tmpdir .. "/plugins/popup_manager.sh",
    "an old popup_manager must not be selected for the new popup_switch CLI"
  )

  os.remove(bin_dir .. "/popup_manager")
  os.execute(string.format("rmdir %q %q", bin_dir, tmpdir))
end)

run_test("resolve_popup_switch: rejects a stale executable and accepts protocol v1", function()
  local tmpdir = os.tmpname() .. "_barista_popup_switch_protocol"
  local bin_dir = tmpdir .. "/bin"
  local scripts_dir = tmpdir .. "/scripts"
  local helper = bin_dir .. "/popup_switch"
  local fallback = tmpdir .. "/plugins/popup_manager.sh"
  os.execute(string.format("mkdir -p %q %q", bin_dir, scripts_dir))
  assert(os.execute(string.format(
    "cp %q %q",
    "scripts/popup_switch_protocol_probe.pl",
    scripts_dir .. "/popup_switch_protocol_probe.pl"
  )))

  local file = assert(io.open(helper, "w"))
  file:write("#!/bin/sh\nprintf '%s\\n' barista-popup-switch-v1\nexit 42\n")
  file:close()
  assert(os.execute(string.format("chmod +x %q", helper)))
  assert_equal(
    binary_resolver.resolve_popup_switch(tmpdir, false, fallback),
    fallback,
    "an executable with no supported switch protocol must fall back"
  )

  file = assert(io.open(helper, "w"))
  file:write("#!/bin/sh\nsleep 4\n")
  file:close()
  local started = assert(io.popen(
    [[/usr/bin/perl -MTime::HiRes=time -e 'printf("%.6f\n", time())']]
  ))
  local started_at = assert(tonumber(started:read("*a")))
  started:close()
  assert_equal(
    binary_resolver.resolve_popup_switch(tmpdir, false, fallback),
    fallback,
    "a hung protocol probe must time out and fall back"
  )
  local finished = assert(io.popen(
    [[/usr/bin/perl -MTime::HiRes=time -e 'printf("%.6f\n", time())']]
  ))
  local elapsed = assert(tonumber(finished:read("*a"))) - started_at
  finished:close()
  assert_true(
    elapsed < 1,
    string.format("a hung helper must not retain the resolver pipe (elapsed %.3fs)", elapsed)
  )

  file = assert(io.open(helper, "w"))
  file:write("#!/bin/sh\nprintf '%s\\n' barista-popup-switch-v1\n")
  file:close()
  assert_equal(
    binary_resolver.resolve_popup_switch(tmpdir, false, fallback),
    helper,
    "a protocol-v1 helper should be selected"
  )

  os.remove(helper)
  os.remove(scripts_dir .. "/popup_switch_protocol_probe.pl")
  os.execute(string.format("rmdir %q %q %q", bin_dir, scripts_dir, tmpdir))
end)
