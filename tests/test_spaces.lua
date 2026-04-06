local spaces = require("spaces")

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
