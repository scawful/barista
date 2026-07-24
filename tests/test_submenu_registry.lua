-- test_submenu_registry.lua - Tests for modules/submenu_registry.lua

local submenu_registry = require("submenu_registry")

local tmpdir = os.tmpname() .. ".d"
os.remove(tmpdir)
assert(os.execute("mkdir -p " .. string.format("%q", tmpdir)))
local test_submenu_file = tmpdir .. "/sketchybar_submenu_list"
local test_popup_file   = tmpdir .. "/sketchybar_popup_list"
local test_topology_file = tmpdir .. "/sketchybar_popup_topology"

local function read_file(path)
  local fh = assert(io.open(path, "r"))
  local content = fh:read("*a")
  fh:close()
  return content
end

local function numbered_names(prefix, count)
  local names = {}
  for index = 1, count do
    table.insert(names, string.format("%s.%03d", prefix, index))
  end
  return names
end

-- Cleanup helper
local function cleanup()
  os.remove(test_submenu_file)
  os.remove(test_submenu_file .. ".tmp")
  os.remove(test_popup_file)
  os.remove(test_popup_file .. ".tmp")
  os.remove(test_topology_file)
  os.remove(test_topology_file .. ".tmp")
end

run_test("write_submenu_list: creates file with names", function()
  cleanup()
  submenu_registry.write_submenu_list({"menu.foo", "menu.bar", "menu.baz"}, tmpdir)
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
  submenu_registry.write_popup_list({"apple_menu", "clock"}, tmpdir)
  local fh = io.open(test_popup_file, "r")
  assert_true(fh ~= nil, "file should exist")
  local content = fh:read("*a")
  fh:close()
  assert_true(content:find("apple_menu") ~= nil, "should contain apple_menu")
  assert_true(content:find("clock") ~= nil, "should contain clock")
  cleanup()
end)

run_test("register: writes legacy lists and one click topology generation", function()
  cleanup()
  submenu_registry.register(
    {"popup1", "popup2"},
    {"sub1", "sub2", "sub3"},
    tmpdir,
    {
      ["sub2"] = { "sub1" },
      ["sub3"] = { "sub2", "sub1" },
    }
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

  local fh3 = assert(io.open(test_topology_file, "r"))
  local content3 = fh3:read("*a")
  fh3:close()
  assert_equal(
    content3,
    table.concat({
      "version\t1",
      "root\tpopup1",
      "root\tpopup2",
      "child\tsub1",
      "child\tsub2",
      "child\tsub3",
      "ancestor\tsub2\tsub1",
      "ancestor\tsub3\tsub1",
      "ancestor\tsub3\tsub2",
      "",
    }, "\n"),
    "click topology should publish roots, children, and sorted ancestor chains together"
  )
  cleanup()
end)

run_test("register: optional generation token is published immediately after version", function()
  cleanup()
  local token = submenu_registry.new_topology_token()
  assert_true(type(token) == "string" and token ~= "", "token should be non-empty")
  assert_true(#token <= 127, "token should fit the topology field bound")
  assert_true(
    not token:find("[%z\t\r\n]"),
    "token should not contain topology delimiters"
  )
  local second_token = submenu_registry.new_topology_token()
  assert_true(second_token ~= token, "successive topology tokens should differ")

  assert_true(submenu_registry.register(
    { "popup1" },
    { "sub1" },
    tmpdir,
    {},
    token
  ))
  assert_equal(
    read_file(test_topology_file),
    table.concat({
      "version\t1",
      "generation\t" .. token,
      "root\tpopup1",
      "child\tsub1",
      "",
    }, "\n"),
    "generation should be the second topology record"
  )
  cleanup()
end)

run_test("write_submenu_list: entries are one per line", function()
  cleanup()
  submenu_registry.write_submenu_list({"item.a", "item.b"}, tmpdir)
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
  submenu_registry.register(nil, {"sub.only"}, tmpdir)
  local fh = io.open(test_popup_file, "r")
  assert_true(fh == nil, "popup file should not exist")
  local fh2 = io.open(test_submenu_file, "r")
  assert_true(fh2 ~= nil, "submenu file should exist")
  fh2:close()
  cleanup()
end)

run_test("register: nil submenus skips submenu file", function()
  cleanup()
  submenu_registry.register({"popup.only"}, nil, tmpdir)
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh == nil, "submenu file should not exist")
  local fh2 = io.open(test_popup_file, "r")
  assert_true(fh2 ~= nil, "popup file should exist")
  fh2:close()
  cleanup()
end)

run_test("write_submenu_list: dedupes repeated names", function()
  cleanup()
  submenu_registry.write_submenu_list({"item.a", "item.a", "item.b"}, tmpdir)
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh ~= nil, "file should exist")
  local lines = {}
  for line in fh:lines() do
    table.insert(lines, line)
  end
  fh:close()
  assert_equal(#lines, 2, "should have 2 unique lines")
  assert_equal(lines[1], "item.a", "first line")
  assert_equal(lines[2], "item.b", "second line")
  cleanup()
end)

run_test("write_submenu_list: empty list still creates authoritative empty file", function()
  cleanup()
  submenu_registry.write_submenu_list({}, tmpdir)
  local fh = io.open(test_submenu_file, "r")
  assert_true(fh ~= nil, "empty file should exist")
  local content = fh:read("*a")
  fh:close()
  assert_equal(content, "", "empty list should write empty file")
  cleanup()
end)

run_test("write_popup_list: atomically replaces the authoritative file", function()
  cleanup()
  local original = assert(io.open(test_popup_file, "w"))
  original:write("old.popup\n")
  original:close()
  submenu_registry.write_popup_list({ "new.popup", "other.popup" }, tmpdir)
  local fh = assert(io.open(test_popup_file, "r"))
  local content = fh:read("*a")
  fh:close()
  assert_equal(content, "new.popup\nother.popup\n", "published registry should contain only the complete new list")
  assert_true(io.open(test_popup_file .. ".tmp", "r") == nil, "atomic publish should not leave a staging file")
  cleanup()
end)

run_test("write_popup_topology: enforces unique root and child bounds", function()
  cleanup()
  local roots = numbered_names("root", 128)
  local children = numbered_names("child", 128)
  assert_true(
    submenu_registry.write_popup_topology(roots, children, {}, tmpdir),
    "128 unique roots and children should publish"
  )

  table.insert(roots, "root.129")
  assert_true(
    not submenu_registry.write_popup_topology(roots, children, {}, tmpdir),
    "129 unique roots should be rejected"
  )
  assert_true(io.open(test_topology_file, "r") == nil, "invalid roots should not publish")

  roots = numbered_names("root", 128)
  table.insert(children, "child.129")
  assert_true(
    not submenu_registry.write_popup_topology(roots, children, {}, tmpdir),
    "129 unique children should be rejected"
  )
  assert_true(io.open(test_topology_file, "r") == nil, "invalid children should not publish")

  roots = numbered_names("root", 128)
  table.insert(roots, roots[1])
  children = numbered_names("child", 128)
  table.insert(children, children[1])
  assert_true(
    submenu_registry.write_popup_topology(roots, children, {}, tmpdir),
    "duplicate names should not count against unique-name bounds"
  )
  cleanup()
end)

run_test("write_popup_topology: enforces unique ancestor relation bound", function()
  cleanup()
  local relations = { ["child.target"] = numbered_names("ancestor", 512) }
  assert_true(
    submenu_registry.write_popup_topology({}, { "child.target" }, relations, tmpdir),
    "512 unique ancestor pairs should publish"
  )

  table.insert(relations["child.target"], "ancestor.513")
  assert_true(
    not submenu_registry.write_popup_topology({}, { "child.target" }, relations, tmpdir),
    "513 unique ancestor pairs should be rejected"
  )
  assert_true(io.open(test_topology_file, "r") == nil, "invalid relations should not publish")

  local duplicates = {}
  for _ = 1, 513 do table.insert(duplicates, "ancestor.same") end
  assert_true(
    submenu_registry.write_popup_topology(
      {},
      { "child.target" },
      { ["child.target"] = duplicates },
      tmpdir
    ),
    "duplicate ancestor pairs should count once"
  )
  cleanup()
end)

run_test("write_popup_topology: validates ASCII and Unicode byte lengths", function()
  cleanup()
  local ascii_127 = string.rep("a", 127)
  local unicode_127 = string.rep("é", 63) .. "a"
  local unicode_128 = string.rep("é", 64)
  assert_equal(#unicode_127, 127, "Lua string length should measure UTF-8 bytes")
  assert_equal(#unicode_128, 128, "Unicode over-limit fixture should be 128 bytes")

  assert_true(
    submenu_registry.write_popup_topology(
      { ascii_127 },
      { unicode_127 },
      {},
      tmpdir
    ),
    "127-byte names should publish"
  )
  assert_true(
    not submenu_registry.write_popup_topology(
      { string.rep("a", 128) },
      {},
      {},
      tmpdir
    ),
    "128-byte ASCII names should be rejected"
  )
  assert_true(
    not submenu_registry.write_popup_topology(
      { unicode_128 },
      {},
      {},
      tmpdir
    ),
    "128-byte Unicode names should be rejected by byte length"
  )
  cleanup()
end)

run_test("write_popup_topology: rejects record delimiters in names", function()
  cleanup()
  for _, delimiter in ipairs({ "\t", "\n", "\r", "\0" }) do
    assert_true(
      not submenu_registry.write_popup_topology(
        { "bad" .. delimiter .. "name" },
        {},
        {},
        tmpdir
      ),
      "reserved name delimiter should be rejected"
    )
    assert_true(
      io.open(test_topology_file, "r") == nil,
      "delimiter-bearing name should not publish"
    )
  end
  cleanup()
end)

run_test("write_popup_topology: publication failure invalidates stale routing", function()
  cleanup()
  local old = assert(io.open(test_topology_file, "w"))
  old:write("version\t1\nroot\tstale.popup\n")
  old:close()

  local real_rename = os.rename
  os.rename = function(from, to)
    if to == test_topology_file then
      return nil, "forced topology publish failure"
    end
    return real_rename(from, to)
  end
  local ok, published = pcall(function()
    return submenu_registry.write_popup_topology(
      { "new.popup" },
      { "new.child" },
      {},
      tmpdir
    )
  end)
  os.rename = real_rename

  assert_true(ok, "forced publication failure should not raise")
  assert_true(not published, "forced publication failure should be reported")
  local stale = io.open(test_topology_file, "r")
  assert_true(stale == nil, "stale topology should be removed so clicks fail open")
  cleanup()
end)

run_test("write_popup_topology: token makes undeletable stale generation inert", function()
  cleanup()
  local old = assert(io.open(test_topology_file, "w"))
  old:write("version\t1\ngeneration\told-token\nroot\tstale.popup\n")
  old:close()

  local real_rename = os.rename
  local real_remove = os.remove
  os.rename = function(from, to)
    if to == test_topology_file then
      return nil, "forced topology publish failure"
    end
    return real_rename(from, to)
  end
  os.remove = function(path)
    if path == test_topology_file then
      return nil, "forced stale topology removal failure"
    end
    return real_remove(path)
  end
  local ok, published = pcall(function()
    return submenu_registry.write_popup_topology(
      { "new.popup" },
      { "new.child" },
      {},
      tmpdir,
      "new-token"
    )
  end)
  os.rename = real_rename
  os.remove = real_remove

  assert_true(ok, "rename and removal failures should not raise")
  assert_true(not published, "failed generation should be reported")
  assert_equal(
    read_file(test_topology_file),
    "version\t1\ngeneration\told-token\nroot\tstale.popup\n",
    "forced removal failure should leave only the old generation"
  )
  -- Click helpers require BARISTA_POPUP_TOPOLOGY_TOKEN=new-token, so this
  -- stale old-token file is rejected even though it could not be unlinked.
  cleanup()
end)

cleanup()
os.execute("rmdir " .. string.format("%q", tmpdir) .. " >/dev/null 2>&1")
