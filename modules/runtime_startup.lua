local runtime_startup = {}

function runtime_startup.wall_time_ms()
  local handle = io.popen("python3 - <<'PY'\nimport time\nprint(time.time_ns() // 1_000_000)\nPY\n")
  if not handle then
    return os.time() * 1000
  end

  local value = (handle:read("*a") or ""):gsub("%s+", "")
  handle:close()

  local numeric = tonumber(value)
  if numeric then
    return numeric
  end

  return os.time() * 1000
end

function runtime_startup.current_time_ms()
  return math.floor(os.clock() * 1000)
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

function runtime_startup.record_duration_event(stats_bin, event_name, duration_ms, opts)
  opts = opts or {}

  if type(stats_bin) ~= "string" or stats_bin == "" then
    return nil
  end
  if type(event_name) ~= "string" or event_name == "" then
    return nil
  end
  if type(duration_ms) ~= "number" or duration_ms < 0 then
    return nil
  end

  local exists = opts.file_exists or file_exists
  if not exists(stats_bin) then
    return nil
  end

  local exec = opts.exec or os.execute
  exec(string.format("%q event %q %d >/dev/null 2>&1 || true", stats_bin, event_name, duration_ms))

  local trace = opts.trace
  local trace_label = opts.trace_label or event_name
  if type(trace) == "function" then
    trace(trace_label .. " " .. tostring(duration_ms))
  end

  return duration_ms
end

function runtime_startup.record_reload_metrics(stats_bin, reload_start_ms, opts)
  opts = opts or {}

  if type(reload_start_ms) ~= "number" or reload_start_ms < 0 then
    return nil
  end

  if type(stats_bin) ~= "string" or stats_bin == "" then
    return nil
  end

  local exists = opts.file_exists or file_exists
  if not exists(stats_bin) then
    return nil
  end

  local now_ms = opts.now_ms or runtime_startup.wall_time_ms
  local duration_ms = now_ms() - reload_start_ms
  if duration_ms < 0 then
    return nil
  end

  local exec = opts.exec or os.execute
  exec(string.format("%q reload >/dev/null 2>&1 || true", stats_bin))
  exec(string.format("%q reload-time %d >/dev/null 2>&1 || true", stats_bin, duration_ms))

  local trace = opts.trace
  if type(trace) == "function" then
    trace("main:reload_ms " .. tostring(duration_ms))
  end

  return duration_ms
end

function runtime_startup.build_space_runtime_subscription(delay_seconds, sketchybar_bin)
  local delay = tonumber(delay_seconds) or 0
  local binary = sketchybar_bin or "sketchybar"

  return string.format(
    "sleep %.1f; %q --subscribe space_runtime space_visual_refresh front_app_switched system_woke",
    delay,
    binary
  )
end

function runtime_startup.build_space_visual_refresh(delay_seconds, script_path, config_dir, scripts_dir)
  local delay = tonumber(delay_seconds) or 0
  local script = script_path or ""
  local config = config_dir or ""
  local scripts = scripts_dir or ""

  return string.format(
    "sleep %.1f; NAME=space_runtime SENDER=manual CONFIG_DIR=%q SCRIPTS_DIR=%q %q >/dev/null 2>&1 || true",
    delay,
    config,
    scripts,
    script
  )
end

return runtime_startup
