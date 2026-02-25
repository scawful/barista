-- Halext-org Dashboard integration for Barista
-- Polls summary endpoint and shows task/event counts in the bar

local halext_org = {}

local json_ok, json = pcall(require, "helpers.lib.json")
if not json_ok then
  json = nil
end

local HOME = os.getenv("HOME") or ""
local AUTH_FILE = HOME .. "/.config/halext/auth.json"
local CACHE_FILE = HOME .. "/.cache/barista/halext-org-summary.json"
local CACHE_TTL = 300  -- 5 minutes
local BASE_URL = "https://org.halext.org/api"

local function path_exists(path)
  if not path or path == "" then return false end
  local handle = io.popen(string.format("test -e %q && printf 1 || printf 0", path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

local function exec(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  return result
end

local function ensure_cache_dir()
  os.execute("mkdir -p " .. HOME .. "/.cache/barista")
end

local function get_auth_token()
  if not json or not path_exists(AUTH_FILE) then return nil end
  local file = io.open(AUTH_FILE, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  return data.access_token or data.token
end

local function is_cache_valid()
  if not path_exists(CACHE_FILE) then return false end
  local handle = io.popen("stat -f %m " .. CACHE_FILE .. " 2>/dev/null")
  if not handle then return false end
  local mtime = tonumber(handle:read("*a") or "0")
  handle:close()
  return mtime and (os.time() - mtime) < CACHE_TTL
end

local function read_cache()
  if not json or not path_exists(CACHE_FILE) then return nil end
  local file = io.open(CACHE_FILE, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, content)
  return ok and type(data) == "table" and data or nil
end

local function write_cache(data)
  if not json then return end
  ensure_cache_dir()
  local ok, encoded = pcall(json.encode, data)
  if not ok then return end
  local file = io.open(CACHE_FILE, "w")
  if not file then return end
  file:write(encoded)
  file:close()
end

local function fetch_summary(force_refresh)
  if not force_refresh and is_cache_valid() then
    return read_cache()
  end

  local token = get_auth_token()
  if not token then
    return read_cache()  -- fallback to cache
  end

  local auth_header = string.format("-H 'Authorization: Bearer %s'", token)
  local cmd = string.format(
    "curl -s -X GET %s '%s/v1/dashboard/summary' 2>/dev/null",
    auth_header, BASE_URL)
  local response = exec(cmd)

  if not response or response == "" then
    return read_cache()
  end

  local ok, data = pcall(json.decode, response)
  if not ok or type(data) ~= "table" then
    return read_cache()
  end

  write_cache(data)
  return data
end

function halext_org.is_available()
  return path_exists(AUTH_FILE)
end

function halext_org.get_status()
  local summary = fetch_summary()
  if not summary then
    return "?", "󰔟", "0xff6c7086"
  end

  local pending = summary.tasks_pending or 0
  local today = summary.tasks_today or 0
  if today > 0 then
    return string.format("%d", today), "󰔟", "0xfff9e2af"
  elseif pending > 0 then
    return string.format("%d", pending), "󰔟", "0xffa6e3a1"
  end
  return "", "󰔟", "0xffa6e3a1"
end

function halext_org.create_menu_items(ctx)
  local summary = fetch_summary()
  local items = {}

  table.insert(items, {
    type = "header",
    name = "halext_org.header",
    label = "Halext Org",
  })

  if not summary then
    table.insert(items, {
      type = "item",
      name = "halext_org.offline",
      icon = "󰈂",
      label = "Not connected",
      icon_color = "0xff6c7086",
    })
  else
    table.insert(items, {
      type = "item",
      name = "halext_org.tasks_pending",
      icon = "󰝖",
      label = string.format("Pending Tasks: %d", summary.tasks_pending or 0),
      icon_color = "0xfff9e2af",
    })

    table.insert(items, {
      type = "item",
      name = "halext_org.tasks_today",
      icon = "󰃭",
      label = string.format("Due Today: %d", summary.tasks_today or 0),
      icon_color = (summary.tasks_today or 0) > 0 and "0xfff38ba8" or "0xffa6e3a1",
    })

    if summary.events_upcoming then
      table.insert(items, {
        type = "item",
        name = "halext_org.events",
        icon = "󰸗",
        label = string.format("Upcoming Events: %d", summary.events_upcoming),
        icon_color = "0xff89b4fa",
      })
    end

    if summary.nerv_hosts_online ~= nil then
      table.insert(items, {
        type = "item",
        name = "halext_org.nerv",
        icon = "󰈀",
        label = string.format("NERV Hosts Online: %d", summary.nerv_hosts_online),
        icon_color = summary.nerv_hosts_online > 0 and "0xffa6e3a1" or "0xfff38ba8",
      })
    end
  end

  table.insert(items, { type = "separator", name = "halext_org.sep1" })

  table.insert(items, {
    type = "item",
    name = "halext_org.open",
    icon = "󰖟",
    label = "Open Dashboard",
    action = "open 'https://org.halext.org'",
  })

  table.insert(items, {
    type = "item",
    name = "halext_org.sync",
    icon = "󰓦",
    label = "Sync Org Tasks",
    action = "python3 " .. HOME .. "/src/tools/org-sync/org-halext-sync.py sync --verbose",
  })

  return items
end

return halext_org
