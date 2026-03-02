-- test_submenu_registry.lua - Tests for modules/submenu_registry.lua

local submenu_registry = require("submenu_registry")

local tmpdir = os.getenv("TMPDIR") or "/tmp"
local test_submenu_file = tmpdir .. "/sketchybar_submenu_list"
local test_popup_file   = tmpdir .. "/sketchybar_popup_list"

-- Cleanup helper
local function cleanup()
  os.remove(test_submenu_file)
  os.remove(test_popup_file)
end

run_test("write_submenu_list: creates file with names", function()
  cleanup()
  submenu_registry.write_submenu_list({"menu.foo", "menu.bar", "menu.baz"})
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh ~= nil, "file should exist")
  local content = fh:read("*a")
  fh:close()
  assert_true(content:find("menu.foo") ~= nil, "should contain menu.foo")
  assert_true(content:find("menu.bar") ~= nil, "should contain menu.bar")
  assert_true(content:find("menu.baz") ~= nil, "should contain menu.baz")
  cleanup()
end)

run_test("write_popup_list: creates file with names", function()
  cleanup()
  submenu_registry.write_popup_list({"apple_menu", "clock"})
  local fh = io.open(test_popup_file, "r")
  assert_true(fh ~= nil, "file should exist")
  local content = fh:read("*a")
  fh:close()
  assert_true(content:find("apple_menu") ~= nil, "should contain apple_menu")
  assert_true(content:find("clock") ~= nil, "should contain clock")
  cleanup()
end)

run_test("register: writes both files", function()
  cleanup()
  submenu_registry.register(
    {"popup1", "popup2"},
    {"sub1", "sub2", "sub3"}
  )
  local fh1 = io.open(test_popup_file, "r")
  assert_true(fh1 ~= nil, "popup file should exist")
  local content1 = fh1:read("*a")
  fh1:close()
  assert_true(content1:find("popup1") ~= nil, "popup1")
  assert_true(content1:find("popup2") ~= nil, "popup2")

  local fh2 = io.open(test_submenu_file, "r")
  assert_true(fh2 ~= nil, "submenu file should exist")
  local content2 = fh2:read("*a")
  fh2:close()
  assert_true(content2:find("sub1") ~= nil, "sub1")
  assert_true(content2:find("sub2") ~= nil, "sub2")
  assert_true(content2:find("sub3") ~= nil, "sub3")
  cleanup()
end)

run_test("write_submenu_list: entries are one per line", function()
  cleanup()
  submenu_registry.write_submenu_list({"item.a", "item.b"})
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh ~= nil, "file should exist")
  local lines = {}
  for line in fh:lines() do
    table.insert(lines, line)
  end
  fh:close()
  assert_equal(#lines, 2, "should have 2 lines")
  assert_equal(lines[1], "item.a", "first line")
  assert_equal(lines[2], "item.b", "second line")
  cleanup()
end)

run_test("register: nil popups skips popup file", function()
  cleanup()
  submenu_registry.register(nil, {"sub.only"})
  local fh = io.open(test_popup_file, "r")
  assert_true(fh == nil, "popup file should not exist")
  local fh2 = io.open(test_submenu_file, "r")
  assert_true(fh2 ~= nil, "submenu file should exist")
  fh2:close()
  cleanup()
end)

run_test("register: nil submenus skips submenu file", function()
  cleanup()
  submenu_registry.register({"popup.only"}, nil)
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh == nil, "submenu file should not exist")
  local fh2 = io.open(test_popup_file, "r")
  assert_true(fh2 ~= nil, "popup file should exist")
  fh2:close()
  cleanup()
end)
