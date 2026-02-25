-- NERV Status integration for Barista
-- Reads nerv-xfer queue status, shows pending/failed counts, host connectivity

local nerv = {}

local HOME = os.getenv("HOME") or ""
local QUEUE_FILE = HOME .. "/.context/nerv-xfer/queue.json"

local json_ok, json = pcall(require, "helpers.lib.json")
if not json_ok then
  json = nil
end

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

local function read_queue()
  if not json or not path_exists(QUEUE_FILE) then
    return {}
  end
  local file = io.open(QUEUE_FILE, "r")
  if not file then return {} end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

local function queue_stats(queue)
  local stats = { pending = 0, running = 0, completed = 0, failed = 0, last_transfer = nil }
  local entries = queue.queue or queue
  if type(entries) ~= "table" then return stats end

  for _, job in ipairs(entries) do
    local status = job.status or "unknown"
    if status == "queued" then
      stats.pending = stats.pending + 1
    elseif status == "running" then
      stats.running = stats.running + 1
    elseif status == "completed" then
      stats.completed = stats.completed + 1
      if job.completed_at then
        if not stats.last_transfer or job.completed_at > stats.last_transfer then
          stats.last_transfer = job.completed_at
        end
      end
    elseif status == "failed" then
      stats.failed = stats.failed + 1
    end
  end
  return stats
end

local function ping_host(ip, timeout)
  timeout = timeout or 1
  local result = exec(string.format(
    "ping -c 1 -W %d %s 2>/dev/null | grep -c 'bytes from'", timeout, ip))
  return tonumber((result or "0"):match("%d+")) or 0 > 0
end

-- Known NERV hosts (Tailscale IPs)
local NERV_HOSTS = {
  { name = "MECHANICA", ip = "100.64.0.1" },
  { name = "halext-nj", ip = "100.64.0.2" },
}

function nerv.is_available()
  return path_exists(QUEUE_FILE) or path_exists(HOME .. "/.config/nerv")
end

function nerv.get_status()
  local queue = read_queue()
  local stats = queue_stats(queue)

  if stats.failed > 0 then
    return string.format("%d!", stats.failed), "󰒍", "0xfff38ba8"
  elseif stats.pending > 0 or stats.running > 0 then
    return string.format("%d", stats.pending + stats.running), "󰒍", "0xfff9e2af"
  end
  return "", "󰒍", "0xffa6e3a1"
end

function nerv.create_menu_items(ctx)
  local queue = read_queue()
  local stats = queue_stats(queue)
  local items = {}

  -- Header
  table.insert(items, {
    type = "header",
    name = "nerv.header",
    label = "NERV Transfer System",
  })

  -- Queue status
  table.insert(items, {
    type = "item",
    name = "nerv.pending",
    icon = "󰄬",
    label = string.format("Pending: %d", stats.pending),
    icon_color = stats.pending > 0 and "0xfff9e2af" or "0xff6c7086",
  })

  table.insert(items, {
    type = "item",
    name = "nerv.failed",
    icon = "󰅜",
    label = string.format("Failed: %d", stats.failed),
    icon_color = stats.failed > 0 and "0xfff38ba8" or "0xff6c7086",
  })

  if stats.last_transfer then
    table.insert(items, {
      type = "item",
      name = "nerv.last_transfer",
      icon = "󰥔",
      label = string.format("Last: %s", stats.last_transfer),
      icon_color = "0xff6c7086",
    })
  end

  table.insert(items, { type = "separator", name = "nerv.sep1" })

  -- Host connectivity
  table.insert(items, {
    type = "header",
    name = "nerv.hosts.header",
    label = "Host Status",
  })

  for _, host in ipairs(NERV_HOSTS) do
    local online = ping_host(host.ip)
    table.insert(items, {
      type = "item",
      name = "nerv.host." .. host.name:lower(),
      icon = online and "󰈀" or "󰈂",
      label = host.name,
      icon_color = online and "0xffa6e3a1" or "0xfff38ba8",
    })
  end

  table.insert(items, { type = "separator", name = "nerv.sep2" })

  -- Actions
  table.insert(items, {
    type = "item",
    name = "nerv.status",
    icon = "󰋼",
    label = "Show Queue Status",
    action = "open -a Terminal ~/src/lab/nerv-xfer/nerv-xfer status",
  })

  table.insert(items, {
    type = "item",
    name = "nerv.run",
    icon = "󰐊",
    label = "Process Queue",
    action = "~/src/lab/nerv-xfer/nerv-xfer run --limit 5",
  })

  return items
end

return nerv
