-- test_tool_locator.lua - Tests for modules/tool_locator.lua

local locator = require("tool_locator")

math.randomseed(os.time())

local function make_temp_dir(name)
  local path = string.format("/tmp/barista_%s_%d_%d", name, os.time(), math.random(100000, 999999))
  local ok = os.execute(string.format("mkdir -p %q", path))
  assert_true(ok == 0 or ok == true, "create temp dir")
  return path
end

local function mkdir(path)
  local ok = os.execute(string.format("mkdir -p %q", path))
  assert_true(ok == 0 or ok == true, "mkdir " .. path)
end

local function write_file(path, content)
  local file = io.open(path, "w")
  assert_true(file ~= nil, "open " .. path)
  file:write(content)
  file:close()
end

local function cleanup(path)
  os.execute(string.format("rm -rf %q", path))
end

run_test("tool_locator.resolve_code_dir: explicit code_dir wins", function()
  local root = make_temp_dir("locator_code")
  local explicit = root .. "/explicit"
  mkdir(explicit .. "/lab")

  local result = locator.resolve_code_dir({
    code_dir = explicit,
    state = { paths = { code_dir = root .. "/state" } },
  })

  assert_equal(result, explicit, "explicit code_dir")
  cleanup(root)
end)

run_test("tool_locator.load_state: reads state.json", function()
  local root = make_temp_dir("locator_state")
  write_file(root .. "/state.json", [[{"modes":{"runtime_backend":"lua"},"integrations":{"yaze":{"enabled":true}}}]])

  local state = locator.load_state(root)
  assert_type(state, "table", "state table")
  assert_equal(state.modes.runtime_backend, "lua", "runtime_backend")
  assert_true(state.integrations.yaze.enabled, "integration enabled")
  cleanup(root)
end)

run_test("tool_locator.resolve_yaze_dir: falls back to hobby/yaze", function()
  local root = make_temp_dir("locator_yaze")
  local code_dir = root .. "/code"
  mkdir(code_dir .. "/lab")
  mkdir(code_dir .. "/hobby/yaze")

  local resolved, ok = locator.resolve_yaze_dir({ code_dir = code_dir })
  assert_true(ok, "found hobby/yaze")
  assert_equal(resolved, code_dir .. "/hobby/yaze", "hobby fallback")
  cleanup(root)
end)

run_test("tool_locator.resolve_afs_studio_root: finds afs_suite layout", function()
  local root = make_temp_dir("locator_afs_suite")
  local code_dir = root .. "/code"
  mkdir(code_dir .. "/lab")
  mkdir(code_dir .. "/lab/afs_suite")

  local resolved, ok = locator.resolve_afs_studio_root({ code_dir = code_dir }, nil)
  assert_true(ok, "found afs_suite root")
  assert_equal(resolved, code_dir .. "/lab/afs_suite", "afs_suite root")
  cleanup(root)
end)

run_test("tool_locator.resolve_afs_studio_binary: finds suite binary", function()
  local root = make_temp_dir("locator_afs_bin")
  local studio_root = root .. "/afs_suite"
  mkdir(studio_root .. "/build_ai/apps/studio")
  write_file(studio_root .. "/build_ai/apps/studio/afs-studio", "#!/bin/sh\n")

  local resolved, ok = locator.resolve_afs_studio_binary(studio_root)
  assert_true(ok, "found studio binary")
  assert_equal(resolved, studio_root .. "/build_ai/apps/studio/afs-studio", "suite binary")
  cleanup(root)
end)

run_test("tool_locator.resolve_afs_browser_app: prefers build over build_ai", function()
  local root = make_temp_dir("locator_afs_browser")
  local code_dir = root .. "/code"
  mkdir(code_dir .. "/lab/afs_suite/build/apps/browser/afs-browser.app")
  mkdir(code_dir .. "/lab/afs_suite/build_ai/apps/browser/afs-browser.app")

  local resolved, ok = locator.resolve_afs_browser_app({ code_dir = code_dir })
  assert_true(ok, "found browser app")
  assert_equal(resolved, code_dir .. "/lab/afs_suite/build/apps/browser/afs-browser.app", "prefers build app")
  cleanup(root)
end)

run_test("tool_locator.resolve_afs_studio_launcher: finds afs-scawful helper", function()
  local root = make_temp_dir("locator_afs_launcher")
  local code_dir = root .. "/code"
  local launcher = code_dir .. "/lab/afs-scawful/scripts/afs/utils/afs-studio"
  mkdir(code_dir .. "/lab/afs-scawful/scripts/afs/utils")
  write_file(launcher, "#!/bin/sh\n")
  local ok = os.execute(string.format("chmod +x %q", launcher))
  assert_true(ok == 0 or ok == true, "chmod afs-studio launcher")

  local resolved, found = locator.resolve_afs_studio_launcher({ code_dir = code_dir })
  assert_true(found, "found studio launcher")
  assert_equal(resolved, launcher, "launcher path")
  cleanup(root)
end)

run_test("tool_locator.resolve_mesen_run: explicit override wins", function()
  local root = make_temp_dir("locator_mesen")
  local bin = root .. "/mesen-run"
  write_file(bin, "#!/bin/sh\n")
  local ok = os.execute(string.format("chmod +x %q", bin))
  assert_true(ok == 0 or ok == true, "chmod mesen-run")

  local resolved, found = locator.resolve_mesen_run({ mesen_run = bin })
  assert_true(found, "found mesen override")
  assert_equal(resolved, bin, "mesen override path")
  cleanup(root)
end)
