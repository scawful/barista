local apple_menu = require("apple_menu_enhanced")

math.randomseed(os.time())

local function command_ok(result)
  return result == true or result == 0
end

local function make_temp_dir(name)
  local path = string.format("/tmp/barista_%s_%d_%d", name, os.time(), math.random(100000, 999999))
  local ok = os.execute(string.format("mkdir -p %q", path))
  assert_true(command_ok(ok), "create temp dir")
  return path
end

local function mkdir(path)
  local ok = os.execute(string.format("mkdir -p %q", path))
  assert_true(command_ok(ok), "mkdir " .. path)
end

local function write_file(path, content)
  local file = io.open(path, "w")
  assert_true(file ~= nil, "open " .. path)
  file:write(content or "")
  file:close()
end

local function chmod_x(path)
  local ok = os.execute(string.format("chmod +x %q", path))
  assert_true(command_ok(ok), "chmod " .. path)
end

local function cleanup(path)
  os.execute(string.format("rm -rf %q", path))
end

local function build_ctx(root, overrides)
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  local state = {
    appearance = {
      menu_item_height = 23,
    },
    menus = {
      apple = {},
      apps = {
        enabled = false,
        items = {},
      },
    },
  }

  local ctx = {
    config_dir = config_dir,
    code_dir = code_dir,
    state = state,
    appearance = state.appearance,
    settings = {
      font = {
        text = "Source Code Pro",
        style_map = { Regular = "Regular", Bold = "Bold", Semibold = "Semibold" },
        sizes = { small = 12 },
      },
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffbac2de",
      BG_SEC_COLR = "0xff1e1e2e",
      SAPPHIRE = "0xff74c7ec",
      TEAL = "0xff94e2d5",
      PEACH = "0xfffab387",
      LAVENDER = "0xffb4befe",
      PINK = "0xfff5c2e7",
      YELLOW = "0xfff9e2af",
      RED = "0xfff38ba8",
      MAGENTA = "0xffcba6f7",
      MAUVE = "0xffcba6f7",
      BLUE = "0xff89b4fa",
      SKY = "0xff89dceb",
      GREEN = "0xffa6e3a1",
      bar = { bg = "0xff11111b" },
    },
    integrations = {},
    integration_flags = {},
    paths = {},
    use_global_apps = false,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    open_path = function(path)
      return "open " .. tostring(path)
    end,
    font_string = function(family, style, size)
      return string.format("%s:%s:%s", family, style, tostring(size))
    end,
  }

  for key, value in pairs(overrides or {}) do
    ctx[key] = value
  end

  return ctx
end

run_test("apple_menu.prepare: keeps AFS Browser but removes duplicate Oracle and AFS Studio rows", function()
  local root = make_temp_dir("apple_menu_prepare_dedup")
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  local browser_app = root .. "/apps/afs-browser.app"
  local studio_root = root .. "/afs_suite"
  local studio_launcher = root .. "/bin/afs-studio"
  local yaze_app = root .. "/apps/yaze.app"
  local mesen_run = root .. "/bin/mesen-run"

  mkdir(config_dir .. "/bin")
  mkdir(code_dir .. "/lab")
  mkdir(browser_app)
  mkdir(studio_root)
  mkdir(root .. "/bin")
  mkdir(yaze_app)
  write_file(config_dir .. "/bin/open_oracle_agent_manager.sh", "#!/bin/sh\nexit 0\n")
  write_file(studio_launcher, "#!/bin/sh\nexit 0\n")
  write_file(mesen_run, "#!/bin/sh\nexit 0\n")
  chmod_x(studio_launcher)
  chmod_x(mesen_run)

  local prepared = apple_menu.prepare(build_ctx(root, {
    paths = {
      afs_browser_app = browser_app,
      afs_studio = studio_root,
      afs_studio_launcher = studio_launcher,
      yaze_app = yaze_app,
      mesen_run = mesen_run,
    },
  }))

  local by_id = {}
  for _, entry in ipairs(prepared.rendered or {}) do
    by_id[entry.id] = entry
  end

  assert_true(by_id.afs_browser ~= nil, "AFS Browser should stay in the Apple menu apps section")
  assert_equal(by_id.afs_browser.label, "AFS Browser", "AFS Browser should stay labeled as the canonical AFS app")
  assert_true(by_id.afs_browser.action:find("afs%-browser%.app", 1, false) ~= nil, "AFS Browser row should open the app bundle")
  assert_nil(by_id.afs_studio, "AFS Studio should no longer appear in the Apple menu")
  assert_nil(by_id.oracle_agent_manager, "Oracle Hub should move out of the Apple menu")
  assert_nil(by_id.yaze, "Yaze should move out of the Apple menu")
  assert_nil(by_id.mesen_oos, "Mesen2 OoS should move out of the Apple menu")

  cleanup(root)
end)

run_test("apple_menu.prepare: AFS Browser falls back to the studio launcher when no browser app exists", function()
  local root = make_temp_dir("apple_menu_prepare_afs_studio_fallback")
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  local afs_root = code_dir .. "/lab/afs"
  local studio_launcher = code_dir .. "/lab/afs-scawful/scripts/afs/utils/afs-studio"

  mkdir(config_dir)
  mkdir(afs_root)
  mkdir(code_dir .. "/lab/afs-scawful/scripts/afs/utils")
  write_file(studio_launcher, "#!/bin/sh\nexit 0\n")
  chmod_x(studio_launcher)

  local prepared = apple_menu.prepare(build_ctx(root, {
    paths = {
      afs = afs_root,
      afs_studio_launcher = studio_launcher,
    },
  }))

  local afs_browser = nil
  for _, entry in ipairs(prepared.rendered or {}) do
    if entry.id == "afs_browser" then
      afs_browser = entry
      break
    end
  end

  assert_true(afs_browser ~= nil, "AFS Browser row should still be rendered")
  assert_equal(afs_browser.label, "AFS Browser", "canonical AFS row should keep its label")
  assert_equal(afs_browser.action, string.format("%q", studio_launcher), "AFS Browser row should fall back to the studio launcher")
  assert_true(afs_browser.missing ~= true, "AFS Browser row should not be marked missing when the studio launcher exists")

  cleanup(root)
end)

run_test("apple_menu.prepare: missing AFS row becomes an explicit build affordance", function()
  local root = make_temp_dir("apple_menu_prepare_afs_missing")
  mkdir(root .. "/config")
  mkdir(root .. "/code/lab")

  local prepared = apple_menu.prepare(build_ctx(root))
  local afs_browser = nil
  for _, entry in ipairs(prepared.rendered or {}) do
    if entry.id == "afs_browser" then
      afs_browser = entry
      break
    end
  end

  assert_true(afs_browser ~= nil, "missing AFS row should still surface a recovery row")
  assert_equal(afs_browser.label, "Build AFS", "missing AFS row should use the explicit build label")
  assert_true(afs_browser.missing == true, "missing AFS row should be marked missing")
  assert_true(afs_browser.action:find("No local AFS desktop surface was found", 1, false) ~= nil, "missing AFS row should explain the missing app surface")

  cleanup(root)
end)
