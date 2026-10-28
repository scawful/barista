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

local function write_text(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

local function pid_file(name)
  return string.format("%s/barista-%s.pid", TMPDIR, name)
end

local function start_token_file(name)
  return string.format("%s/barista-%s.start", TMPDIR, name)
end

local function unique_start_token(name)
  return string.format("%s-%d-%s", tostring(name or "daemon"), os.time(), tostring({}))
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

-- ps exposes command arguments too. A substring can match an editor, rg, or
-- shell command that merely mentions a daemon, so require the whole invocation.
local function command_matches(command, fragments)
  command = trim(command)
  if not command or command == "" or not fragments or #fragments == 0 then
    return false
  end
  local executable, arguments = command:match("^(%S+)%s+(.+)$")
  local interpreter = executable and executable:match("([^/]+)$")
  if interpreter == "bash" or interpreter == "sh" or interpreter == "zsh" then
    -- Daemon shell scripts appear as /bin/bash /path/script daemon. Never
    -- interpret -c command strings or shell options as a daemon script path.
    if arguments:sub(1, 1) ~= "-" then
      command = arguments
    end
  end
  for _, fragment in ipairs(fragments) do
    if command == fragment then
      return true
    end
  end
  return false
end

runtime_daemon.matches_daemon_process = command_matches

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

  local handle = io.popen("ps -axo pid=,command= 2>/dev/null")
  if not handle then
    return pids
  end

  local output = handle:read("*a") or ""
  handle:close()
  for line in output:gmatch("[^\r\n]+") do
    local pid, command = line:match("^%s*(%d+)%s+(.-)%s*$")
    if pid and command and command_matches(command, fragments) and not seen[pid] then
      seen[pid] = true
      table.insert(pids, pid)
    end
  end

  return pids
end

local function kill_pids(pids, tracef, reason, trace_prefix, fragments)
  local seen = {}
  local killed_any = false
  trace_prefix = trace_prefix or "runtime_daemon:daemon"
  for _, pid in ipairs(pids or {}) do
    if pid and pid ~= "" and not seen[pid] then
      -- Verify again after discovery, then retain identity through escalation.
      local command = process_command(pid)
      if command_matches(command, fragments) then
        seen[pid] = command
        os.execute(string.format("kill %s >/dev/null 2>&1", pid))
        killed_any = true
        if type(tracef) == "function" then
          tracef(string.format("%s_%s %s", trace_prefix, reason or "killed", pid))
        end
      end
    end
  end

  if not killed_any then
    return
  end

  os.execute("sleep 0.05")
  for pid, command in pairs(seen) do
    if process_command(pid) == command then
      os.execute(string.format("kill -9 %s >/dev/null 2>&1", pid))
      if type(tracef) == "function" then
        tracef(string.format("%s_%s_force %s", trace_prefix, reason or "killed", pid))
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
  local write = opts.write_text or write_text
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
  local token_path = opts.start_token_file or start_token_file(name)
  local fragments = collect_fragments(expected_fragment, opts.match_fragments)
  local previous_pid = trim(read(file) or ""):match("^(%d+)$")
  local force_restart = opts.force_restart == true
  local trace_prefix = string.format("runtime_daemon:%s", name:gsub("[^%w]+", "_"))

  if previous_pid then
    local alive, existing_command = running(previous_pid, fragments)
    if alive then
      if force_restart then
        killer({ previous_pid }, tracef, "restarting", trace_prefix, fragments)
      else
        tracef(trace_prefix .. "_already_running " .. previous_pid)
        return true, "already_running"
      end
    else
      local old_alive = running(previous_pid, fragments)
      if old_alive then
        killer({ previous_pid }, tracef, "killed_previous", trace_prefix, fragments)
      elseif existing_command then
        tracef(trace_prefix .. "_pid_mismatch " .. previous_pid)
      end
    end
  end

  if force_restart then
    killer(find_pids(fragments), tracef, "killed_stale", trace_prefix, fragments)
  end

  local launch_token = unique_start_token(name)
  if not write(token_path, launch_token .. "\n") then
    tracef(trace_prefix .. "_token_write_failed")
    return false, "token_write_failed"
  end
  tracef(trace_prefix .. "_token_written")
  if trim(read(token_path) or "") ~= launch_token then
    tracef(trace_prefix .. "_superseded")
    return false, "superseded"
  end

  local launch_script = table.concat({
    "expected=" .. shell_quote(launch_token),
    "token_file=" .. shell_quote(token_path),
    "pid_file=" .. shell_quote(file),
    "current=$(cat \"$token_file\" 2>/dev/null || true)",
    "[ \"$current\" = \"$expected\" ] || exit 0",
    "echo $$ > \"$pid_file\"",
    "exec " .. command,
  }, "; ")
  local launch_command = string.format(
    "nohup /bin/sh -c %s >/dev/null 2>&1 &",
    shell_quote(launch_script)
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
  local token_path = opts.start_token_file or start_token_file(name)
  local fragments = collect_fragments(expected_fragment, opts.match_fragments)
  local stopped = false
  local pid = trim(read(file) or ""):match("^(%d+)$")
  if pid then
    local alive = running(pid, fragments)
    if alive then
      killer({ pid }, tracef, "stopped", string.format("runtime_daemon:%s", name:gsub("[^%w]+", "_")), fragments)
      stopped = true
    end
  end
  local stale = find_pids(fragments)
  if #stale > 0 then
    killer(stale, tracef, "killed_stale", string.format("runtime_daemon:%s", name:gsub("[^%w]+", "_")), fragments)
    stopped = true
  end
  remove(file)
  remove(token_path)
  return stopped or pid ~= nil
end

function runtime_daemon.ensure_widget_daemon(binary_path, opts)
  if not binary_path or binary_path == "" then
    return false, "missing_binary"
  end
  opts = type(opts) == "table" and opts or {}
  local expected_fragment = tostring(binary_path) .. " daemon"
  local env_prefix = type(opts.env_prefix) == "string" and opts.env_prefix or ""
  local command = string.format("%s%s daemon", env_prefix, shell_quote(binary_path))
  return ensure_named_daemon("widget-manager", command, expected_fragment, opts)
end

local function config_dir(opts)
  return opts.config_dir or os.getenv("BARISTA_CONFIG_DIR")
    or ((os.getenv("HOME") or "") .. "/.config/sketchybar")
end

function runtime_daemon.stop_widget_daemon(opts)
  opts = type(opts) == "table" and opts or {}
  local root = config_dir(opts)
  local selected = opts.binary_path or (root .. "/build/bin/widget_manager")
  opts.match_fragments = opts.match_fragments or {
    root .. "/build/bin/widget_manager daemon",
    root .. "/bin/widget_manager daemon",
  }
  return stop_named_daemon("widget-manager", selected .. " daemon", opts)
end

local function runtime_context_fragments(script_path, opts)
  local root = opts.config_dir or script_path:match("^(.*)/scripts/[^/]+$") or config_dir(opts)
  local fragments = {}
  for _, path in ipairs({
    script_path,
    opts.helper_path or (root .. "/bin/runtime_context_helper"),
    root .. "/build/bin/runtime_context_helper",
  }) do
    for _, action in ipairs({ "daemon", "refresh-front-app", "fresh-front-app" }) do
      if path == script_path and action == "refresh-front-app" then
        table.insert(fragments, path .. " refresh front-app")
      else
        table.insert(fragments, path .. " " .. action)
      end
    end
  end
  return fragments
end

function runtime_daemon.ensure_runtime_context_daemon(script_path, opts)
  if not script_path or script_path == "" then
    return false, "missing_script"
  end
  opts = type(opts) == "table" and opts or {}
  local expected_fragment = tostring(script_path) .. " daemon"
  local command
  if opts.lua_only then
    command = string.format("/usr/bin/env BARISTA_LUA_ONLY=1 %s daemon", shell_quote(script_path))
  else
    command = string.format("%s daemon", shell_quote(script_path))
  end
  opts.match_fragments = opts.match_fragments or runtime_context_fragments(script_path, opts)
  return ensure_named_daemon("runtime-context", command, expected_fragment, opts)
end

function runtime_daemon.stop_runtime_context_daemon(opts)
  opts = type(opts) == "table" and opts or {}
  local script_path = opts.script_path or (config_dir(opts) .. "/scripts/runtime_context.sh")
  opts.match_fragments = opts.match_fragments or runtime_context_fragments(script_path, opts)
  return stop_named_daemon("runtime-context", script_path .. " daemon", opts)
end

return runtime_daemon
