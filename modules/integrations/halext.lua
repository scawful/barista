-- halext-org Integration Module
-- Provides REST API integration with halext-org server for tasks, calendar, and LLM suggestions

local halext = {}
local json = require("json")

local HOME = os.getenv("HOME")
local CACHE_DIR = HOME .. "/.config/sketchybar/cache"
local TASKS_CACHE = CACHE_DIR .. "/halext_tasks.json"
local CALENDAR_CACHE = CACHE_DIR .. "/halext_calendar.json"
local CACHE_TTL = 300 -- 5 minutes

-- Ensure cache directory exists
os.execute("mkdir -p " .. CACHE_DIR)

-- Utility: Check if cache is valid
local function is_cache_valid(cache_file, ttl)
  local file = io.open(cache_file, "r")
  if not file then return false end
  file:close()

  local stat_cmd = "stat -f %m " .. cache_file .. " 2>/dev/null || stat -c %Y " .. cache_file .. " 2>/dev/null"
  local handle = io.popen(stat_cmd)
  local timestamp = handle:read("*a")
  handle:close()

  if not timestamp or timestamp == "" then return false end

  local mtime = tonumber(timestamp)
  local now = os.time()
  return (now - mtime) < ttl
end

-- Utility: Read cache file
local function read_cache(cache_file)
  local file = io.open(cache_file, "r")
  if not file then return nil end

  local contents = file:read("*a")
  file:close()

  local ok, decoded = pcall(json.decode, contents)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil
end

-- Utility: Write cache file
local function write_cache(cache_file, data)
  local ok, encoded = pcall(json.encode, data)
  if not ok then return false end

  local file = io.open(cache_file, "w")
  if not file then return false end

  file:write(encoded)
  file:close()
  return true
end

-- API: Make HTTP request to halext-org server
local function api_request(config, endpoint, method)
  method = method or "GET"

  if not config.enabled or config.server_url == "" then
    return nil, "halext-org integration not enabled or configured"
  end

  local url = config.server_url .. endpoint
  local auth_header = ""

  if config.api_key ~= "" then
    auth_header = string.format("-H 'Authorization: Bearer %s'", config.api_key)
  end

  local cmd = string.format(
    "curl -s -X %s %s '%s' 2>/dev/null",
    method,
    auth_header,
    url
  )

  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute API request"
  end

  local response = handle:read("*a")
  local success = handle:close()

  if not success or response == "" then
    return nil, "API request failed or returned empty response"
  end

  local ok, decoded = pcall(json.decode, response)
  if ok and type(decoded) == "table" then
    return decoded, nil
  end

  return nil, "Failed to parse API response"
end

-- Fetch tasks from halext-org
function halext.get_tasks(config, force_refresh)
  if not force_refresh and is_cache_valid(TASKS_CACHE, config.sync_interval or CACHE_TTL) then
    return read_cache(TASKS_CACHE)
  end

  local data, err = api_request(config, "/api/tasks", "GET")
  if err then
    -- Return cached data if API fails
    return read_cache(TASKS_CACHE) or {}
  end

  write_cache(TASKS_CACHE, data)
  return data
end

-- Fetch calendar events from halext-org
function halext.get_calendar_events(config, force_refresh)
  if not force_refresh and is_cache_valid(CALENDAR_CACHE, config.sync_interval or CACHE_TTL) then
    return read_cache(CALENDAR_CACHE)
  end

  local data, err = api_request(config, "/api/calendar/today", "GET")
  if err then
    -- Return cached data if API fails
    return read_cache(CALENDAR_CACHE) or {}
  end

  write_cache(CALENDAR_CACHE, data)
  return data
end

-- Get LLM suggestions based on current context
function halext.get_suggestions(config, context)
  context = context or "general"

  local endpoint = string.format("/api/llm/suggest?context=%s", context)
  local data, err = api_request(config, endpoint, "GET")

  if err then
    return { error = err }
  end

  return data
end

-- Format tasks for menu display
function halext.format_tasks_for_menu(tasks)
  if not tasks or #tasks == 0 then
    return {
      {
        type = "item",
        name = "halext.no_tasks",
        icon = "",
        label = "No tasks",
        action = "",
      }
    }
  end

  local menu_items = {}
  local count = 0

  for _, task in ipairs(tasks) do
    if count >= 10 then break end -- Limit to 10 tasks

    local icon = task.completed and "" or ""
    local label = task.title or "Untitled"

    if task.priority == "high" then
      icon = ""
    end

    table.insert(menu_items, {
      type = "item",
      name = "halext.task." .. (task.id or count),
      icon = icon,
      label = label,
      action = string.format("open '%s/tasks/%s'", task.server_url or "", task.id or ""),
    })

    count = count + 1
  end

  return menu_items
end

-- Format calendar events for menu display
function halext.format_calendar_for_menu(events)
  if not events or #events == 0 then
    return {
      {
        type = "item",
        name = "halext.no_events",
        icon = "",
        label = "No events today",
        action = "",
      }
    }
  end

  local menu_items = {}
  local count = 0

  for _, event in ipairs(events) do
    if count >= 5 then break end -- Limit to 5 events

    local time = event.start_time or ""
    local label = string.format("%s %s", time, event.title or "Untitled")

    table.insert(menu_items, {
      type = "item",
      name = "halext.event." .. (event.id or count),
      icon = "",
      label = label,
      action = string.format("open '%s/calendar/%s'", event.server_url or "", event.id or ""),
    })

    count = count + 1
  end

  return menu_items
end

-- Test connection to halext-org server
function halext.test_connection(config)
  local data, err = api_request(config, "/api/health", "GET")

  if err then
    return false, err
  end

  if data and data.status == "ok" then
    return true, "Connected successfully"
  end

  return false, "Server returned unexpected response"
end

-- Clear all caches
function halext.clear_cache()
  os.execute("rm -f " .. TASKS_CACHE)
  os.execute("rm -f " .. CALENDAR_CACHE)
  return true
end

-- Create a widget displaying task count
function halext.create_task_widget(config)
  if not config.enabled or not config.show_tasks then
    return nil
  end

  local tasks = halext.get_tasks(config)
  local incomplete_count = 0

  for _, task in ipairs(tasks) do
    if not task.completed then
      incomplete_count = incomplete_count + 1
    end
  end

  return {
    icon = "",
    label = tostring(incomplete_count),
    popup = {
      align = "left",
    },
  }
end

return halext
