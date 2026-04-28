local project_shortcuts = require("project_shortcuts")

local function make_temp_dir(name)
  local tmpdir = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local safe_name = tostring(name):gsub("[^%w_-]", "_")
  local template = string.format("%s/barista_%s.XXXXXX", tmpdir, safe_name)
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

run_test("project_shortcuts.normalize_entry: relative paths resolve against code dir", function()
  local root = make_temp_dir("project_shortcuts_relative")
  local code_dir = root .. "/code"
  mkdir(code_dir .. "/hobby/oracle-agent-manager")

  local entry = project_shortcuts.normalize_entry(code_dir, "terminal", {
    label = "Oracle Agent Manager",
    path = "hobby/oracle-agent-manager",
  }, 1)

  assert_equal(entry.path, code_dir .. "/hobby/oracle-agent-manager", "resolved project path")
  assert_true(entry.available, "project should be available")
  assert_true(entry.action:match("Terminal"), "terminal action should use Terminal")
  cleanup(root)
end)

run_test("project_shortcuts.load: empty file is authoritative", function()
  local root = make_temp_dir("project_shortcuts_empty")
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  mkdir(config_dir .. "/data")
  mkdir(code_dir .. "/lab")
  write_file(config_dir .. "/data/project_shortcuts.json", "[]\n")

  local loaded = project_shortcuts.load(config_dir, code_dir, {
    menus = {
      apps = {
        file = "data/project_shortcuts.json",
        items = {
          { label = "Fallback", path = "lab/fallback" },
        },
      },
    },
  })

  assert_equal(#loaded.items, 0, "empty file should override fallback items")
  cleanup(root)
end)

run_test("project_shortcuts.load: legacy menus.projects still works", function()
  local root = make_temp_dir("project_shortcuts_legacy")
  local config_dir = root .. "/config"
  local code_dir = root .. "/code"
  mkdir(config_dir .. "/data")
  mkdir(code_dir .. "/lab/legacy")
  write_file(config_dir .. "/data/project_shortcuts.json", [[
[
  { "id": "legacy_app", "label": "Legacy App", "path": "lab/legacy" }
]
]])

  local loaded = project_shortcuts.load(config_dir, code_dir, {
    menus = {
      projects = {
        file = "data/project_shortcuts.json",
      },
    },
  })

  assert_equal(#loaded.items, 1, "legacy projects alias should still load")
  assert_equal(loaded.items[1].section, "apps", "legacy section should normalize to apps")
  cleanup(root)
end)

run_test("project_shortcuts.normalize_entry: applies project-specific default colors", function()
  local root = make_temp_dir("project_shortcuts_colors")
  local code_dir = root .. "/code"
  mkdir(code_dir .. "/lab/barista")

  local entry = project_shortcuts.normalize_entry(code_dir, "terminal", {
    id = "barista",
    label = "Barista",
    path = "lab/barista",
  }, 1)

  assert_equal(entry.icon_color, "0xfffab387", "barista icon color")
  assert_equal(entry.label_color, "0xfff8ceb4", "barista label color")
  cleanup(root)
end)

run_test("project_shortcuts.normalize_entry: action entries stay available without a project path", function()
  local entry = project_shortcuts.normalize_entry("/tmp/code", "terminal", {
    id = "barista_control",
    label = "Barista Control",
    action = "open -a Barista",
  }, 1)

  assert_true(entry.available, "action-only entry should be available")
  assert_equal(entry.icon, "󰓹", "barista icon")
  assert_equal(entry.icon_color, "0xfffab387", "barista icon color")
  assert_equal(entry.label_color, "0xfff8ceb4", "barista label color")
  assert_equal(entry.section, "apps", "default app section")
end)

run_test("project_shortcuts.normalize_entry: preserves build metadata for missing apps", function()
  local entry = project_shortcuts.normalize_entry("/tmp/code", "terminal", {
    id = "local_tool",
    label = "Local Tool",
    action = "",
    available = false,
    build_action = "/bin/bash /tmp/build_local_tool.sh",
    build_label = "Build Local Tool",
    missing_message = "Local Tool.app is missing. Rebuild the app?",
    missing_title = "Barista · Local Tool",
    missing_action = "open /tmp/local-tool",
  }, 1)

  assert_true(not entry.available, "missing app should stay unavailable until built")
  assert_equal(entry.build_action, "/bin/bash /tmp/build_local_tool.sh", "build action should be preserved")
  assert_equal(entry.build_label, "Build Local Tool", "build label should be preserved")
  assert_equal(entry.missing_title, "Barista · Local Tool", "missing title should be preserved")
  assert_equal(entry.missing_action, "open /tmp/local-tool", "missing fallback action should be preserved")
end)
