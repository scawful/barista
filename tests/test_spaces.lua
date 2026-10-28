local spaces = require("spaces")

-- Never let a test write the real replay file under $HOME. The scratch
-- directory is removed afterwards even when the test fails.
local function with_scratch_replay(fn)
  local dir = os.tmpname()
  os.remove(dir)
  local ok, err = pcall(fn, dir .. "/state/yabai_signals.sh")
  os.execute(string.format("rm -rf %q", dir))
  if not ok then
    error(err, 0)
  end
end

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
  with_scratch_replay(function(replay_path)
  local executed = nil
  local manager = spaces.create(
    "/tmp/config",
    "/tmp/plugins",
    "/opt/homebrew/bin/sketchybar",
    "/custom/bin/yabai",
    function(cmd) executed = cmd end,
    function() return false end,
    false,
    replay_path
  )

  manager.watch_spaces()

  assert_true(executed ~= nil, "watch_spaces should execute a signal registration command")
  assert_true(executed:find("/custom/bin/yabai", 1, true) ~= nil, "signal registration should use the resolved yabai binary path")
  assert_true(executed:find("event=space_changed", 1, true) ~= nil, "space_changed signal should be registered")
  assert_true(executed:find("BARISTA_REASON", 1, true) ~= nil and executed:find("space_changed", 1, true) ~= nil, "space_changed should route through refresh_spaces diff path")
  assert_true(executed:find("refresh_spaces.sh", 1, true) ~= nil, "signals should call refresh_spaces.sh")
  end)
end)

run_test("spaces: watch_spaces saves its signals for yabai to replay after a restart", function()
  local executed, replay = nil, nil
  with_scratch_replay(function(replay_path)
    local manager = spaces.create("/tmp/config", "/tmp/plugins", "/opt/homebrew/bin/sketchybar", "/custom/bin/yabai",
      function(cmd) executed = cmd end, function() return false end, false, replay_path)

    manager.watch_spaces()

    local file = io.open(replay_path)
    assert_true(file ~= nil, "watch_spaces should write the replay script")
    replay = file:read("*a")
    file:close()
  end)
  assert_true(replay:find("event=mission_control_exit", 1, true) ~= nil, "replay should include the Mission Control guard")
  for command in executed:gmatch("[^;]+;?") do
    local line = command:gsub("^%s+", ""):gsub(";$", "")
    assert_true(replay:find(line, 1, true) ~= nil, "replay should match what was registered: " .. line)
  end
end)

run_test("spaces: Lua-only refresh paths disable compiled helpers", function()
  with_scratch_replay(function(replay_path)
  local executed = {}
  local manager = spaces.create(
    "/tmp/config",
    "/tmp/plugins",
    "/opt/homebrew/bin/sketchybar",
    "/custom/bin/yabai",
    function(cmd) table.insert(executed, cmd) end,
    function() return false end,
    true,
    replay_path
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
end)

run_test("spaces: display-scoped widgets cover every space SketchyBar can mask", function()
  local yabai_queried = false
  local manager = spaces.create("/tmp/config", "/tmp/plugins", "/opt/homebrew/bin/sketchybar", "/custom/bin/yabai",
    function() end, function() yabai_queried = true; return true end, false, "/dev/null")
  local list = manager.get_associated_spaces()
  local indexes = {}
  for index in list:gmatch("%d+") do
    table.insert(indexes, tonumber(index))
  end
  assert_equal(#indexes, 31, "the list should name spaces 1-31, including ones created after load")
  assert_equal(indexes[1], 1, "the list should start at space 1")
  assert_equal(indexes[31], 31, "space 31 is the last bit of SketchyBar's 32-bit mask")
  assert_true(not yabai_queried, "the list should not depend on the spaces live at load")
end)
