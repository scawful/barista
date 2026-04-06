-- runtime_daemon.lua - Manage Barista background helper daemons.

local runtime_daemon = {}

local TMPDIR = os.getenv("TMPDIR") or "/tmp"

local function trim(value)
  if type(value) ~= "string" then
    return value
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_text(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function pid_file(name)
  return string.format("%s/barista-%s.pid", TMPDIR, name)
end

local function collect_fragments(primary, extras)
  local fragments = {}
  local seen = {}

  local function add(value)
    if type(value) ~= "string" then
      return
    end
    value = trim(value)
    if value == "" or seen[value] then
      return
    end
    seen[value] = true
    table.insert(fragments, value)
  end

  if type(primary) == "table" then
    for _, value in ipairs(primary) do
      add(value)
    end
  else
    add(primary)
  end

  if type(extras) == "table" then
    for _, value in ipairs(extras) do
      add(value)
    end
  else
    add(extras)
  end

  return fragments
end

local function command_matches(command, fragments)
  if not command or command == "" then
    return false
  end
  if not fragments or #fragments == 0 then
    return true
  end
  for _, fragment in ipairs(fragments) do
    if command:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

local function process_command(pid)
  local handle = io.popen(string.format("ps -p %s -o command= 2>/dev/null", tostring(pid)))
  if not handle then
    return nil
  end
  local command = trim(handle:read("*a") or "")
  handle:close()
  if command == "" then
    return nil
  end
  return command
end

local function process_running(pid, expected_fragment, extra_fragments)
  if not pid or pid == "" then
    return false, nil
  end
  local command = process_command(pid)
  if not command then
    return false, nil
  end
  local fragments = collect_fragments(expected_fragment, extra_fragments)
  if not command_matches(command, fragments) then
    return false, command
  end
  return true, command
end

local function matching_pids(expected_fragment, extra_fragments)
  local fragments = collect_fragments(expected_fragment, extra_fragments)
  if #fragments == 0 then
    return {}
  end
  local pids = {}
  local seen = {}

  for _, fragment in ipairs(fragments) do
    local handle = io.popen(string.format("pgrep -f %s 2>/dev/null", shell_quote(fragment)))
    if handle then
      local output = handle:read("*a") or ""
      handle:close()
      for line in output:gmatch("[^\r\n]+") do
        local pid = trim(line):match("^(%d+)$")
        if pid and not seen[pid] then
          seen[pid] = true
          table.insert(pids, pid)
        end
      end
    end
  end

  return pids
end

local function kill_pids(pids, tracef, reason)
  local seen = {}
  for _, pid in ipairs(pids or {}) do
    if pid and pid ~= "" and not seen[pid] then
      seen[pid] = true
      os.execute(string.format("kill %s >/dev/null 2>&1", pid))
      if type(tracef) == "function" then
        tracef(string.format("runtime_daemon:widget_manager_%s %s", reason or "killed", pid))
      end
    end
  end
  os.execute("sleep 0.1")
  for pid in pairs(seen) do
    if process_command(pid) then
      os.execute(string.format("kill -9 %s >/dev/null 2>&1", pid))
      if type(tracef) == "function" then
        tracef(string.format("runtime_daemon:widget_manager_%s_force %s", reason or "killed", pid))
      end
    end
  end
end

function runtime_daemon.normalize_mode(mode)
  if mode == nil or mode == "" then
    return "auto"
  end
  mode = trim(tostring(mode):lower())
  if mode == "0" or mode == "off" or mode == "false" or mode == "disable" or mode == "disabled" then
    return "disabled"
  end
  if mode == "1" or mode == "on" or mode == "true" or mode == "enable" or mode == "enabled" then
    return "enabled"
  end
  return "auto"
end

function runtime_daemon.resolve_widget_daemon_mode(state, env_get)
  local getenv = env_get or os.getenv
  local env_mode = getenv("BARISTA_WIDGET_DAEMON")
  if env_mode and env_mode ~= "" then
    return runtime_daemon.normalize_mode(env_mode)
  end
  if type(state) == "table" and type(state.modes) == "table" then
    return runtime_daemon.normalize_mode(state.modes.widget_daemon)
  end
  return "auto"
end

function runtime_daemon.should_enable_widget_daemon(state, opts)
  opts = type(opts) == "table" and opts or {}
  local mode = runtime_daemon.resolve_widget_daemon_mode(state, opts.getenv)
  if mode == "disabled" then
    return false
  end
  if opts.lua_only then
    return false
  end
  local binary_path = opts.binary_path
  if not binary_path or binary_path == "" then
    return false
  end
  return true
end

local function ensure_named_daemon(name, command, expected_fragment, opts)
  opts = type(opts) == "table" and opts or {}
  if not command or command == "" then
    return false, "missing_command"
  end
  if not expected_fragment or expected_fragment == "" then
    return false, "missing_expected_fragment"
  end

  local trace = opts.trace
  local read = opts.read_text or read_text
  local running = opts.process_running or process_running
  local find_pids = opts.matching_pids or matching_pids
  local killer = opts.kill_pids or kill_pids
  local execute = opts.execute or os.execute
  local function tracef(message)
    if type(trace) == "function" then
      trace(message)
    end
  end

  local file = opts.pid_file or pid_file(name)
  local fragments = collect_fragments(expected_fragment, opts.match_fragments)
  local primary_fragment = fragments[1] or expected_fragment
  local previous_pid = trim(read(file) or ""):match("^(%d+)$")
  local force_restart = opts.force_restart == true
  local trace_prefix = string.format("runtime_daemon:%s", name:gsub("[^%w]+", "_"))

  if previous_pid then
    local alive, existing_command = running(previous_pid, fragments)
    if alive then
      if force_restart then
        killer({ previous_pid }, tracef, "restarting")
      else
        tracef(trace_prefix .. "_already_running " .. previous_pid)
        return true, "already_running"
      end
    else
      local old_alive = running(previous_pid, fragments)
      if old_alive then
        killer({ previous_pid }, tracef, "killed_previous")
      elseif existing_command then
        tracef(trace_prefix .. "_pid_mismatch " .. previous_pid)
      end
    end
  end

  if force_restart then
    killer(find_pids(fragments), tracef, "killed_stale")
  end

  local launch_command = string.format(
    "nohup %s >/dev/null 2>&1 & echo $! > %s",
    command,
    shell_quote(file)
  )
  local ok = execute(launch_command)
  if ok then
    tracef(trace_prefix .. "_started")
    return true, "started"
  end

  tracef(trace_prefix .. "_start_failed")
  return false, "start_failed"
end

local function stop_named_daemon(name, expected_fragment, opts)
  opts = type(opts) == "table" and opts or {}
  local trace = opts.trace
  local read = opts.read_text or read_text
  local running = opts.process_running or process_running
  local find_pids = opts.matching_pids or matching_pids
  local killer = opts.kill_pids or kill_pids
  local remove = opts.remove or os.remove
  local function tracef(message)
    if type(trace) == "function" then
      trace(message)
    end
  end

  local file = opts.pid_file or pid_file(name)
  local fragments = collect_fragments(expected_fragment, opts.match_fragments)
  local stopped = false
  local pid = trim(read(file) or ""):match("^(%d+)$")
  if pid then
    local alive = running(pid, fragments)
    if alive then
      killer({ pid }, tracef, "stopped")
      stopped = true
    end
  end
  local stale = find_pids(fragments)
  if #stale > 0 then
    killer(stale, tracef, "killed_stale")
    stopped = true
  end
  remove(file)
  return stopped or pid ~= nil
end

function runtime_daemon.ensure_widget_daemon(binary_path, opts)
  if not binary_path or binary_path == "" then
    return false, "missing_binary"
  end
  local expected_fragment = tostring(binary_path) .. " daemon"
  local command = string.format("%s daemon", shell_quote(binary_path))
  return ensure_named_daemon("widget-manager", command, expected_fragment, opts)
end

function runtime_daemon.stop_widget_daemon(opts)
  return stop_named_daemon("widget-manager", "widget_manager daemon", opts)
end

function runtime_daemon.ensure_runtime_context_daemon(script_path, opts)
  if not script_path or script_path == "" then
    return false, "missing_script"
  end
  local expected_fragment = tostring(script_path) .. " daemon"
  local command = string.format("%s daemon", shell_quote(script_path))
  opts = type(opts) == "table" and opts or {}
  opts.match_fragments = opts.match_fragments or {
    "runtime_context.sh daemon",
    "runtime_context_helper daemon",
    "runtime_context_helper refresh-front-app",
  }
  return ensure_named_daemon("runtime-context", command, expected_fragment, opts)
end

function runtime_daemon.stop_runtime_context_daemon(opts)
  opts = type(opts) == "table" and opts or {}
  opts.match_fragments = opts.match_fragments or {
    "runtime_context.sh daemon",
    "runtime_context_helper daemon",
    "runtime_context_helper refresh-front-app",
  }
  return stop_named_daemon("runtime-context", "runtime_context.sh daemon", opts)
end

return runtime_daemon
