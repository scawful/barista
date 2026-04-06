local runtime_daemon = require("runtime_daemon")

run_test("runtime_daemon.resolve_widget_daemon_mode: default auto", function()
  assert_equal(runtime_daemon.resolve_widget_daemon_mode({ modes = {} }, function() return nil end), "auto", "default mode")
end)

run_test("runtime_daemon.resolve_widget_daemon_mode: env override wins", function()
  local result = runtime_daemon.resolve_widget_daemon_mode(
    { modes = { widget_daemon = "disabled" } },
    function(key)
      if key == "BARISTA_WIDGET_DAEMON" then
        return "enabled"
      end
      return nil
    end
  )
  assert_equal(result, "enabled", "env override")
end)

run_test("runtime_daemon.should_enable_widget_daemon: requires compiled runtime", function()
  local enabled = runtime_daemon.should_enable_widget_daemon(
    { modes = { widget_daemon = "auto" } },
    { binary_path = "/tmp/widget_manager", lua_only = false }
  )
  assert_true(enabled, "daemon should enable when binary is present")

  local disabled = runtime_daemon.should_enable_widget_daemon(
    { modes = { widget_daemon = "auto" } },
    { binary_path = "", lua_only = false }
  )
  assert_true(not disabled, "daemon should stay disabled without binary")
end)

run_test("runtime_daemon.ensure_runtime_context_daemon: missing script is rejected", function()
  local ok, reason = runtime_daemon.ensure_runtime_context_daemon("", {})
  assert_true(not ok, "runtime context daemon should reject an empty script path")
  assert_equal(reason, "missing_script", "missing script reason")
end)

run_test("runtime_daemon.stop_runtime_context_daemon: stops helper family", function()
  local seen_fragments = nil
  local killed = {}
  local removed = nil

  local stopped = runtime_daemon.stop_runtime_context_daemon({
    pid_file = "/tmp/runtime-context-test.pid",
    read_text = function(path)
      assert_equal(path, "/tmp/runtime-context-test.pid", "pid file path")
      return "123\n"
    end,
    process_running = function(pid, fragments)
      if pid == "123" then
        return true, "/Users/scawful/.config/sketchybar/scripts/runtime_context.sh daemon"
      end
      return false, nil
    end,
    matching_pids = function(fragments)
      seen_fragments = fragments
      return { "123", "456", "789" }
    end,
    kill_pids = function(pids, _, reason)
      table.insert(killed, { pids = pids, reason = reason })
    end,
    remove = function(path)
      removed = path
    end,
  })

  assert_true(stopped, "stop should report success when family members are found")
  assert_equal(removed, "/tmp/runtime-context-test.pid", "pid file removed")
  assert_equal(#killed, 2, "expected targeted pid stop and stale family cleanup")
  assert_equal(killed[1].reason, "stopped", "first reason")
  assert_equal(killed[2].reason, "killed_stale", "second reason")
  assert_equal(table.concat(seen_fragments, "|"), "runtime_context.sh daemon|runtime_context_helper daemon|runtime_context_helper refresh-front-app", "family fragments")
end)
