local interface_extensions = require("interface_extensions")

local function make_temp_dir(name)
  local tmpdir = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local template = string.format("%s/barista_%s.XXXXXX", tmpdir, tostring(name):gsub("[^%w_-]", "_"))
  local handle = io.popen("mktemp -d " .. string.format("%q", template))
  assert_true(handle ~= nil, "run mktemp")
  local path = handle:read("*l")
  local ok = handle:close()
  assert_true((ok == true or ok == 0) and path and path ~= "", "create temp dir")
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

run_test("interface_extensions: missing local file is empty and safe", function()
  local root = make_temp_dir("interface_extensions_missing")
  local loaded = interface_extensions.load(root .. "/config", root .. "/code", {
    menus = {
      extensions = {
        file = "data/interface_extensions.local.json",
      },
    },
  })
  assert_equal(#loaded.items, 0, "missing local file should not expose rows")
  cleanup(root)
end)

run_test("interface_extensions: filters by pack and surface", function()
  local root = make_temp_dir("interface_extensions_pack_surface")
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  mkdir(config_dir .. "/data")
  write_file(config_dir .. "/data/extensions.json", [[
[
  {
    "id": "personal_only",
    "pack": "personal",
    "label": "Personal Only",
    "script": "scripts/open_local_workflow.sh",
    "args": ["scawfulbot"],
    "surfaces": ["apple_menu", "front_app"],
    "order": 20
  },
  {
    "id": "work_only",
    "pack": "work",
    "label": "Work Only",
    "url": "https://example.com",
    "surface": "apple_menu",
    "order": 10
  }
]
]])

  local apple = interface_extensions.for_surface(config_dir, code_dir, {
    machine = { menu_packs = { "personal" } },
    menus = { extensions = { file = "data/extensions.json" } },
  }, "apple_menu")

  assert_equal(#apple, 1, "only personal pack should load")
  assert_equal(apple[1].id, "personal_only", "personal row id")
  assert_true(apple[1].action:find("open_local_workflow%.sh", 1) ~= nil, "script action should resolve")
  assert_true(apple[1].action:find("scawfulbot", 1, true) ~= nil, "script args should be included")

  local cc = interface_extensions.for_surface(config_dir, code_dir, {
    machine = { menu_packs = { "personal" } },
    menus = { extensions = { file = "data/extensions.json" } },
  }, "control_center")
  assert_equal(#cc, 0, "surface filter should hide non-matching rows")
  cleanup(root)
end)

run_test("interface_extensions: inline items can enable a pack locally", function()
  local rows = interface_extensions.for_surface("/tmp/config", "/tmp/code", {
    machine = { menu_packs = {} },
    menus = {
      extensions = {
        packs = { "personal" },
        items = {
          {
            id = "local",
            pack = "personal",
            label = "Local",
            command = "echo ${CODE_DIR}",
            surface = "front_app",
          },
        },
      },
    },
  }, "front_app")
  assert_equal(#rows, 1, "local pack override should enable inline item")
  assert_true(rows[1].action:find("/tmp/code", 1, true) ~= nil, "template should expand")
end)
