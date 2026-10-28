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
  local removed = {}

  local stopped = runtime_daemon.stop_runtime_context_daemon({
    config_dir = "/Users/example/.config/sketchybar",
    pid_file = "/tmp/runtime-context-test.pid",
    start_token_file = "/tmp/runtime-context-test.start",
    read_text = function(path)
      assert_equal(path, "/tmp/runtime-context-test.pid", "pid file path")
      return "123\n"
    end,
    process_running = function(pid, fragments)
      if pid == "123" then
        return true, "/Users/example/.config/sketchybar/scripts/runtime_context.sh daemon"
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
      table.insert(removed, path)
    end,
  })

  assert_true(stopped, "stop should report success when family members are found")
  assert_equal(table.concat(removed, "|"), "/tmp/runtime-context-test.pid|/tmp/runtime-context-test.start", "pid and token files removed")
  assert_equal(#killed, 2, "expected targeted pid stop and stale family cleanup")
  assert_equal(killed[1].reason, "stopped", "first reason")
  assert_equal(killed[2].reason, "killed_stale", "second reason")
  assert_equal(#seen_fragments, 9, "shell plus installed/build helper family")
  for _, fragment in ipairs(seen_fragments) do
    assert_true(fragment:find("/Users/example/.config/sketchybar/", 1, true) == 1,
      "cleanup must stay inside the selected runtime")
  end
end)

run_test("runtime_daemon.ensure_runtime_context_daemon: superseded launcher does not start", function()
  local files = {}
  local execute_calls = 0

  local ok, reason = runtime_daemon.ensure_runtime_context_daemon("/tmp/runtime_context.sh", {
    pid_file = "/tmp/runtime-context-test.pid",
    start_token_file = "/tmp/runtime-context-test.start",
    read_text = function(path)
      if path == "/tmp/runtime-context-test.pid" then
        return nil
      end
      if path == "/tmp/runtime-context-test.start" then
        return "newer-launch-token\n"
      end
      return files[path]
    end,
    write_text = function(path, content)
      files[path] = content
      return true
    end,
    matching_pids = function()
      return {}
    end,
    execute = function()
      execute_calls = execute_calls + 1
      return true
    end,
  })

  assert_true(not ok, "superseded launch should abort")
  assert_equal(reason, "superseded", "superseded reason")
  assert_equal(execute_calls, 0, "superseded launch should not execute")
end)

run_test("runtime_daemon.ensure_runtime_context_daemon: launch command is token-guarded", function()
  local files = {}
  local launched = nil

  local ok, reason = runtime_daemon.ensure_runtime_context_daemon("/tmp/runtime_context.sh", {
    pid_file = "/tmp/runtime-context-test.pid",
    start_token_file = "/tmp/runtime-context-test.start",
    read_text = function(path)
      return files[path]
    end,
    write_text = function(path, content)
      files[path] = content
      return true
    end,
    matching_pids = function()
      return {}
    end,
    execute = function(command)
      launched = command
      return true
    end,
  })

  assert_true(ok, "guarded launch should succeed")
  assert_equal(reason, "started", "launch reason")
  assert_true(type(launched) == "string" and launched:find("nohup /bin/sh %-c ", 1, false) ~= nil, "launch should use a guarded shell wrapper")
  assert_true(launched:find("cat \"$token_file\"", 1, true) ~= nil, "launch should verify the current start token")
  assert_true(launched:find("echo $$ > \"$pid_file\"", 1, true) ~= nil, "launch should write the pid from the wrapper shell")
  assert_true(launched:find("exec ", 1, true) ~= nil and launched:find("/tmp/runtime_context.sh", 1, true) ~= nil, "launch should still exec the requested daemon")
end)

run_test("runtime_daemon.ensure_runtime_context_daemon: lua-only launch disables compiled helper", function()
  local files = {}
  local launched = nil

  local ok, reason = runtime_daemon.ensure_runtime_context_daemon("/tmp/runtime_context.sh", {
    lua_only = true,
    pid_file = "/tmp/runtime-context-lua-test.pid",
    start_token_file = "/tmp/runtime-context-lua-test.start",
    read_text = function(path)
      return files[path]
    end,
    write_text = function(path, content)
      files[path] = content
      return true
    end,
    matching_pids = function()
      return {}
    end,
    execute = function(command)
      launched = command
      return true
    end,
  })

  assert_true(ok, "lua-only runtime context launch should succeed")
  assert_equal(reason, "started", "lua-only launch reason")
  assert_true(
    type(launched) == "string" and launched:find("/usr/bin/env BARISTA_LUA_ONLY=1", 1, true) ~= nil,
    "lua-only launch should export the helper-disable flag"
  )
end)

run_test("runtime_daemon process identity: excludes commands that mention another daemon", function()
  local root = "/Users/example/Config With Spaces"
  local shell = root .. "/scripts/runtime_context.sh daemon"
  local helper = root .. "/bin/runtime_context_helper daemon"
  local fragments = { shell, helper }
  assert_true(runtime_daemon.matches_daemon_process("/bin/bash " .. shell, fragments), "shell daemon")
  assert_true(runtime_daemon.matches_daemon_process(helper, fragments), "native helper")
  assert_true(not runtime_daemon.matches_daemon_process("/bin/zsh -c " .. shell, fragments), "shell command text")
  assert_true(not runtime_daemon.matches_daemon_process("rg " .. helper, fragments), "search text")
  assert_true(not runtime_daemon.matches_daemon_process("/other/config/bin/runtime_context_helper daemon", fragments), "other config")
  assert_true(not runtime_daemon.matches_daemon_process(helper .. " --other", fragments), "unexpected process args")
  assert_true(not runtime_daemon.matches_daemon_process(helper, {}), "missing identity must fail closed")
end)

run_test("runtime_daemon cleanup: never escalates a pid whose command changed", function()
  local original_popen, original_execute = io.popen, os.execute
  local commands, reads = {}, 0
  local ok, err = pcall(function()
    io.popen = function(command)
      assert_true(command:find("ps -p 424242", 1, true) ~= nil, "only fixture pid queried")
      reads = reads + 1
      local value = reads == 1 and "/fixture/bin/widget_manager daemon" or "/unrelated/editor"
      return { read = function() return value end, close = function() return true end }
    end
    os.execute = function(command)
      table.insert(commands, command)
      return true
    end
    runtime_daemon.stop_widget_daemon({
      config_dir = "/fixture",
      read_text = function() return nil end,
      matching_pids = function() return { "424242" } end,
      remove = function() return true end,
    })
  end)
  io.popen, os.execute = original_popen, original_execute
  assert_true(ok, tostring(err))
  assert_equal(commands[1], "kill 424242 >/dev/null 2>&1", "TERM existing fixture process")
  assert_equal(#commands, 2, "TERM plus wait; changed command must not receive KILL")
end)

run_test("runtime_daemon cleanup: stale discovery never terminates an unrelated process", function()
  local original_popen, original_execute = io.popen, os.execute
  local commands = {}
  local ok, err = pcall(function()
    io.popen = function()
      return { read = function() return "/unrelated/editor" end, close = function() return true end }
    end
    os.execute = function(command)
      table.insert(commands, command)
      return true
    end
    runtime_daemon.stop_widget_daemon({
      config_dir = "/fixture",
      read_text = function() return nil end,
      matching_pids = function() return { "424242" } end,
      remove = function() return true end,
    })
  end)
  io.popen, os.execute = original_popen, original_execute
  assert_true(ok, tostring(err))
  assert_equal(#commands, 0, "reused pid must not receive any signal")
end)
