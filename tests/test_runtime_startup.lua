local runtime_startup = require("runtime_startup")

run_test("main startup wiring: commits and captures config timing before queue flush", function()
  local file = assert(io.open("main.lua", "r"))
  local source = file:read("*a")
  file:close()

  local end_config_pos = assert(source:find("sbar.end_config()", 1, true))
  local timing_pos = assert(source:find("local config_build_duration_ms", end_config_pos, true))
  local flush_pos = assert(source:find("post_config_queue:flush", end_config_pos, true))
  assert_true(end_config_pos < timing_pos and timing_pos < flush_pos,
    "main should commit config and stop config timing before dispatching post-config work")
end)

run_test("runtime_startup post-config queue: defers and flushes actions in order", function()
  local timeline = { "config" }
  local queue = runtime_startup.new_post_config_queue()

  assert_true(queue:enqueue_command("first", { background = true }), "background command should enqueue")
  assert_true(queue:enqueue_call(function()
    table.insert(timeline, "call:second")
  end), "callback should enqueue")
  assert_true(queue:enqueue_command("third"), "foreground command should enqueue")
  assert_equal(queue:size(), 3, "all actions should remain pending before config commit")
  assert_equal(table.concat(timeline, "|"), "config", "nothing should execute before the queue is flushed")

  table.insert(timeline, "end_config")
  local flushed = queue:flush({
    exec = function(command)
      table.insert(timeline, "exec:" .. command)
    end,
    exec_background = function(command)
      table.insert(timeline, "background:" .. command)
    end,
  })

  assert_equal(flushed, 3, "flush should report the executed action count")
  assert_equal(queue:size(), 0, "flush should drain the queue")
  assert_equal(
    table.concat(timeline, "|"),
    "config|end_config|background:first|call:second|exec:third",
    "post-config actions should preserve FIFO order"
  )
  assert_equal(queue:flush({}), 0, "a second flush should be a no-op")
end)

run_test("runtime_startup post-config queue: schedules leading sleeps with the native delay", function()
  local queue = runtime_startup.new_post_config_queue()
  local timeline = {}
  local scheduled_seconds = nil
  local scheduled_callback = nil

  queue:enqueue_command("sleep 0.2; refresh-spaces", { background = true })
  local flushed = queue:flush({
    exec = function(command)
      table.insert(timeline, "exec:" .. command)
    end,
    exec_background = function(command)
      table.insert(timeline, "background:" .. command)
    end,
    delay = function(seconds, callback)
      scheduled_seconds = seconds
      scheduled_callback = callback
    end,
  })

  assert_equal(flushed, 1, "scheduled commands should count as flushed actions")
  assert_equal(scheduled_seconds, 0.2, "native delay should receive the parsed sleep duration")
  assert_type(scheduled_callback, "function", "native delay should receive a callback")
  assert_equal(#timeline, 0, "the command should not launch a shell sleeper")

  scheduled_callback()
  assert_equal(table.concat(timeline, "|"), "background:refresh-spaces",
    "the delayed callback should preserve background execution without the shell sleep")
end)

run_test("runtime_startup post-config queue: falls back when native delay rejects scheduling", function()
  local queue = runtime_startup.new_post_config_queue()
  local commands = {}
  local errors = {}
  queue:enqueue_command("sleep 1.0; subscribe", { background = true })
  queue:enqueue_command("sleep 1.0; move")

  queue:flush({
    exec = function(command)
      table.insert(commands, command)
    end,
    exec_background = function(command)
      table.insert(commands, "background:" .. command)
    end,
    delay = function()
      error("delay unavailable")
    end,
    on_delay_error = function(err)
      table.insert(errors, tostring(err))
    end,
  })

  assert_equal(table.concat(commands, "|"), "background:subscribe|move",
    "failed native scheduling should preserve execution mode without shell sleepers")
  assert_equal(#errors, 1, "native delay failures should be reported once per flush")
end)

run_test("runtime_startup post-config queue: reports a failed callback and continues", function()
  local queue = runtime_startup.new_post_config_queue()
  local timeline = {}
  queue:enqueue_call(function()
    error("watch failed")
  end)
  queue:enqueue_command("subscribe")

  local flushed = queue:flush({
    exec = function(command)
      table.insert(timeline, "exec:" .. command)
    end,
    on_action_error = function(kind, err)
      table.insert(timeline, kind .. ":" .. tostring(err):match("watch failed"))
    end,
  })

  assert_equal(flushed, 2, "callback failures should not change the dispatched action count")
  assert_equal(table.concat(timeline, "|"), "call:watch failed|exec:subscribe",
    "a failed callback should be reported without dropping later startup actions")
end)

run_test("runtime_startup.wall_time_ms: prefers fast helper and falls back", function()
  local commands = {}
  local responses = {
    false,
    {
      read = function()
        return "4567\n"
      end,
      close = function() end,
    },
  }

  local value = runtime_startup.wall_time_ms({
    popen = function(command)
      table.insert(commands, command)
      return table.remove(responses, 1)
    end,
    fallback_time = function()
      return 9
    end,
  })

  assert_equal(value, 4567, "wall time should use the first successful helper result")
  assert_equal(#commands, 2, "wall time should try the next helper when the first one is unavailable")
  assert_true(commands[1]:find("Time::HiRes", 1, true) ~= nil, "perl helper should be attempted first")
  assert_true(commands[2]:find("python3", 1, true) ~= nil, "python helper should be the fallback")

  local fallback_value = runtime_startup.wall_time_ms({
    popen = function()
      return nil
    end,
    fallback_time = function()
      return 7
    end,
  })

  assert_equal(fallback_value, 7000, "wall time should fall back to second-resolution time when helpers are unavailable")
end)

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
