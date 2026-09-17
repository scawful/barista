local spaces = require("spaces")

run_test("spaces: display JSON IDs are numeric, sorted, and deduplicated", function()
  local json = [[
    [
      {"arrangement-id": 10},
      {"arrangement-id": "02"},
      {"arrangement-id": 2},
      {"arrangement-id": 1e1},
      {"arrangement-id": -1},
      {"arrangement-id": 3.5},
      {"nested": {"arrangement-id": "7"}}
    ]
  ]]
  assert_equal(
    spaces.normalize_display_ids(json, "arrangement-id"),
    "2,7,10",
    "display IDs should normalize numeric spellings before sorting and deduplication"
  )
  assert_nil(
    spaces.normalize_display_ids('[{"arrangement-id":"bad"}]', "arrangement-id"),
    "nonnumeric display IDs should be rejected"
  )
  assert_nil(
    spaces.normalize_display_ids('[{"arrangement-id":2}', "arrangement-id"),
    "malformed JSON should be rejected before display extraction"
  )
end)

run_test("spaces: watch_spaces uses resolved yabai binary for signals", function()
  local executed = nil
  local manager = spaces.create(
    "/tmp/config",
    "/tmp/plugins",
    "/opt/homebrew/bin/sketchybar",
    "/custom/bin/yabai",
    function(cmd) executed = cmd end,
    function() return false end
  )

  manager.watch_spaces()

  assert_true(executed ~= nil, "watch_spaces should execute a signal registration command")
  assert_true(executed:find("/custom/bin/yabai", 1, true) ~= nil, "signal registration should use the resolved yabai binary path")
  assert_true(executed:find("event=space_changed", 1, true) ~= nil, "space_changed signal should be registered")
  assert_true(executed:find("BARISTA_REASON", 1, true) ~= nil and executed:find("space_changed", 1, true) ~= nil, "space_changed should route through refresh_spaces diff path")
  assert_true(executed:find("refresh_spaces.sh", 1, true) ~= nil, "signals should call refresh_spaces.sh")
end)

run_test("spaces: Lua-only refresh paths disable compiled helpers", function()
  local executed = {}
  local manager = spaces.create(
    "/tmp/config",
    "/tmp/plugins",
    "/opt/homebrew/bin/sketchybar",
    "/custom/bin/yabai",
    function(cmd) table.insert(executed, cmd) end,
    function() return false end,
    true
  )

  manager.refresh_spaces()
  manager.watch_spaces()

  assert_true(
    executed[1]:find("/usr/bin/env BARISTA_LUA_ONLY=1", 1, true) ~= nil,
    "direct Lua-only refresh should propagate the compiled-helper gate"
  )
  assert_true(
    executed[2]:find("/usr/bin/env BARISTA_LUA_ONLY=1", 1, true) ~= nil,
    "Lua-only yabai signal actions should propagate the compiled-helper gate"
  )
end)
