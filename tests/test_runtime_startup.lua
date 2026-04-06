local runtime_startup = require("runtime_startup")

run_test("runtime_startup.record_reload_metrics: records reload commands and traces duration", function()
  local executed = {}
  local traces = {}

  local duration = runtime_startup.record_reload_metrics("/tmp/barista-stats.sh", 1000, {
    file_exists = function(path)
      assert_equal(path, "/tmp/barista-stats.sh", "stats path should be forwarded")
      return true
    end,
    now_ms = function()
      return 1825
    end,
    exec = function(cmd)
      table.insert(executed, cmd)
      return 0
    end,
    trace = function(message)
      table.insert(traces, message)
    end,
  })

  assert_equal(duration, 825, "duration should be returned")
  assert_equal(#executed, 2, "two stats commands should be emitted")
  assert_true(executed[1]:find("reload >/dev/null 2>&1", 1, true) ~= nil, "reload command should be emitted")
  assert_true(executed[2]:find("reload%-time 825") ~= nil, "reload-time command should include measured duration")
  assert_equal(traces[1], "main:reload_ms 825", "trace should include measured duration")
end)

run_test("runtime_startup.record_reload_metrics: skips missing stats file", function()
  local executed = {}
  local duration = runtime_startup.record_reload_metrics("/tmp/missing-stats.sh", 1000, {
    file_exists = function()
      return false
    end,
    exec = function(cmd)
      table.insert(executed, cmd)
      return 0
    end,
  })

  assert_nil(duration, "missing stats file should skip recording")
  assert_equal(#executed, 0, "no commands should run when stats file is missing")
end)

run_test("runtime_startup.record_duration_event: records named duration events", function()
  local executed = {}
  local traces = {}

  local duration = runtime_startup.record_duration_event("/tmp/barista-stats.sh", "config_build_time", 412, {
    file_exists = function(path)
      assert_equal(path, "/tmp/barista-stats.sh", "stats path should be forwarded")
      return true
    end,
    exec = function(cmd)
      table.insert(executed, cmd)
      return 0
    end,
    trace = function(message)
      table.insert(traces, message)
    end,
    trace_label = "main:config_build_ms",
  })

  assert_equal(duration, 412, "duration should be returned")
  assert_equal(#executed, 1, "one event command should be emitted")
  assert_true(executed[1]:find("event", 1, true) ~= nil, "event command should be emitted")
  assert_true(executed[1]:find("config_build_time", 1, true) ~= nil, "event name should be included")
  assert_true(executed[1]:find("412", 1, true) ~= nil, "duration should be included")
  assert_equal(traces[1], "main:config_build_ms 412", "trace should include the configured trace label")
end)

run_test("runtime_startup.record_duration_events: batches named duration events", function()
  local executed = {}
  local traces = {}

  local recorded = runtime_startup.record_duration_events("/tmp/barista-stats.sh", {
    { name = "config_build_time", duration_ms = 412, trace_label = "main:config_build_ms" },
    { name = "config_menu_render_time", duration_ms = 210, trace_label = "main:config_menu_render_ms" },
  }, {
    file_exists = function(path)
      assert_equal(path, "/tmp/barista-stats.sh", "stats path should be forwarded")
      return true
    end,
    exec = function(cmd)
      table.insert(executed, cmd)
      return 0
    end,
    trace = function(message)
      table.insert(traces, message)
    end,
  })

  assert_equal(recorded, 2, "two duration events should be recorded")
  assert_equal(#executed, 1, "batched duration events should use one shell execution")
  assert_true(executed[1]:find("events-batch", 1, true) ~= nil, "batched duration events should call events-batch")
  assert_true(executed[1]:find("config_build_time\t412", 1, true) ~= nil, "batched payload should include config_build_time")
  assert_true(executed[1]:find("config_menu_render_time\t210", 1, true) ~= nil, "batched payload should include config_menu_render_time")
  assert_equal(traces[1], "main:config_build_ms 412", "first trace should include config_build_time")
  assert_equal(traces[2], "main:config_menu_render_ms 210", "second trace should include config_menu_render_time")
end)

run_test("runtime_startup.build_space_runtime_subscription: includes expected events", function()
  local command = runtime_startup.build_space_runtime_subscription(1.0, "/opt/homebrew/bin/sketchybar")
  assert_true(command:find("sleep 1%.0;", 1) ~= nil, "command should include post-config delay")
  assert_true(command:find("space_runtime", 1, true) ~= nil, "command should subscribe the hidden runtime item")
  assert_true(command:find("space_visual_refresh", 1, true) ~= nil, "command should include visual refresh event")
  assert_true(command:find("front_app_switched", 1, true) ~= nil, "command should include front app switching")
  assert_true(command:find("space_change", 1, true) == nil, "runtime item should not subscribe to topology triggers directly")
end)

run_test("runtime_startup.build_space_visual_refresh: triggers one delayed authoritative refresh", function()
  local command = runtime_startup.build_space_visual_refresh(
    0.8,
    "/Users/scawful/.config/sketchybar/plugins/space_visuals.sh",
    "/Users/scawful/.config/sketchybar",
    "/Users/scawful/.config/sketchybar/scripts"
  )
  assert_true(command:find("sleep 0%.8;", 1) ~= nil, "command should include sync delay")
  assert_true(command:find("NAME=space_runtime", 1, true) ~= nil, "command should target the hidden runtime item context")
  assert_true(command:find("SENDER=startup_sync", 1, true) ~= nil, "command should run the authoritative startup-sync pass directly")
  assert_true(command:find("/plugins/space_visuals.sh", 1, true) ~= nil, "command should execute the space visuals script")
  assert_true(command:find(">/dev/null 2>&1 || true", 1, true) ~= nil, "command should stay best-effort")
end)
