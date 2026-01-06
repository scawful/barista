-- workspace.lua - Workspace Integration for Barista
-- Provides ~/src workspace status for menu bar display

local workspace = {}
local json = require("json")

local HOME = os.getenv("HOME")
local WS_ROOT = os.getenv("WS_ROOT") or HOME .. "/src"
local WS_CACHE_DIR = HOME .. "/.workspace/cache"
local BARISTA_CACHE = HOME .. "/.config/sketchybar/cache"
local DIRTY_CACHE = WS_CACHE_DIR .. "/dirty.txt"
local PROJECTS_CACHE = WS_CACHE_DIR .. "/projects.json"
local CACHE_TTL = 300 -- 5 minutes

-- Ensure cache directories exist
os.execute("mkdir -p " .. WS_CACHE_DIR)
os.execute("mkdir -p " .. BARISTA_CACHE)

-- Utility: Check if cache is valid
local function is_cache_valid(cache_file, ttl)
  local file = io.open(cache_file, "r")
  if not file then return false end
  file:close()

  local stat_cmd = "stat -f %m " .. cache_file .. " 2>/dev/null"
  local handle = io.popen(stat_cmd)
  local timestamp = handle:read("*a")
  handle:close()

  if not timestamp or timestamp == "" then return false end

  local mtime = tonumber(timestamp)
  local now = os.time()
  return (now - mtime) < ttl
end

-- Utility: Read file contents
local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  return contents
end

-- Utility: Execute command and get output
local function exec(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  return result
end

-- Buckets configuration
local BUCKETS = {
  { name = "hobby", path = WS_ROOT .. "/hobby", icon = "" },
  { name = "lab", path = WS_ROOT .. "/lab", icon = "" },
  { name = "halext", path = WS_ROOT .. "/halext/products", icon = "" },
  { name = "tools", path = WS_ROOT .. "/tools", icon = "" },
}

-- Key projects to track
local KEY_PROJECTS = {
  { name = "yaze", path = "hobby/yaze", icon = "" },
  { name = "oracle", path = "hobby/oracle-of-secrets", icon = "" },
  { name = "afs", path = "lab/afs", icon = "" },
  { name = "fashion-suite", path = "halext/products/fashion-suite", icon = "" },
}

-- Get git status for a repo
local function get_repo_status(repo_path)
  local full_path = WS_ROOT .. "/" .. repo_path

  -- Check if directory exists
  local check = io.open(full_path .. "/.git", "r")
  if not check then return nil end
  check:close()

  local branch = exec("git -C " .. full_path .. " branch --show-current 2>/dev/null"):gsub("%s+$", "")
  local dirty = exec("git -C " .. full_path .. " status --porcelain 2>/dev/null | wc -l"):gsub("%s+$", "")

  return {
    name = repo_path:match("[^/]+$"),
    path = repo_path,
    branch = branch,
    dirty = tonumber(dirty) or 0,
  }
end

-- Scan all repos for dirty status
function workspace.scan_dirty_repos()
  local dirty_repos = {}

  for _, bucket in ipairs(BUCKETS) do
    local find_cmd = "find " .. bucket.path .. " -maxdepth 2 -type d -name '.git' 2>/dev/null"
    local result = exec(find_cmd)

    if result then
      for git_dir in result:gmatch("[^\n]+") do
        local repo_path = git_dir:match("(.+)/.git$")
        if repo_path then
          local dirty = exec("git -C " .. repo_path .. " status --porcelain 2>/dev/null | wc -l"):gsub("%s+$", "")
          local count = tonumber(dirty) or 0
          if count > 0 then
            local name = repo_path:match("[^/]+$")
            table.insert(dirty_repos, {
              name = name,
              bucket = bucket.name,
              dirty = count,
            })
          end
        end
      end
    end
  end

  return dirty_repos
end

-- Get workspace summary
function workspace.get_summary(config, force_refresh)
  config = config or {}
  local ttl = config.cache_ttl or CACHE_TTL

  -- Try to use ws tool if available
  if not force_refresh then
    local ws_check = exec("command -v ws >/dev/null 2>&1 && echo 'yes'")
    if ws_check and ws_check:match("yes") then
      local ws_status = exec("ws status --json 2>/dev/null")
      if ws_status and ws_status ~= "" then
        local ok, data = pcall(json.decode, ws_status)
        if ok and type(data) == "table" then
          return data
        end
      end
    end
  end

  -- Fallback: scan filesystem
  local dirty_repos = workspace.scan_dirty_repos()
  local key_status = {}

  for _, proj in ipairs(KEY_PROJECTS) do
    local status = get_repo_status(proj.path)
    if status then
      status.icon = proj.icon
      table.insert(key_status, status)
    end
  end

  return {
    dirty_count = #dirty_repos,
    dirty_repos = dirty_repos,
    key_projects = key_status,
    timestamp = os.time(),
  }
end

-- Get count of dirty repos for widget display
function workspace.get_dirty_count()
  local summary = workspace.get_summary()
  return summary.dirty_count or 0
end

-- Format projects for menu display
function workspace.format_for_menu(summary)
  local items = {}

  -- Header
  table.insert(items, {
    type = "header",
    name = "ws.header",
    label = "Workspace Status",
  })

  -- Key projects
  for _, proj in ipairs(summary.key_projects or {}) do
    local icon = proj.dirty > 0 and "" or ""
    local label = string.format("%s %s", proj.name, proj.branch or "")
    if proj.dirty > 0 then
      label = label .. string.format(" +%d", proj.dirty)
    end

    table.insert(items, {
      type = "item",
      name = "ws.project." .. proj.name,
      icon = icon,
      label = label,
      action = string.format("cd '%s/%s' && $TERMINAL", WS_ROOT, proj.path),
    })
  end

  -- Dirty count summary
  local dirty_count = summary.dirty_count or 0
  if dirty_count > 0 then
    table.insert(items, {
      type = "divider",
    })
    table.insert(items, {
      type = "item",
      name = "ws.dirty_summary",
      icon = "",
      label = string.format("%d dirty repos", dirty_count),
      action = "syshelp wstatus",
    })
  end

  -- Quick actions
  table.insert(items, {
    type = "divider",
  })
  table.insert(items, {
    type = "item",
    name = "ws.action.status",
    icon = "",
    label = "Full Status",
    action = "syshelp workspace",
  })
  table.insert(items, {
    type = "item",
    name = "ws.action.refresh",
    icon = "",
    label = "Refresh",
    action = "syshelp wsrefresh",
  })

  return items
end

-- Create widget for menu bar
function workspace.create_widget(config)
  if not config or not config.enabled then
    return nil
  end

  local dirty_count = workspace.get_dirty_count()

  local icon = config.icon or ""
  local color = "0xffa6e3a1" -- Green when clean

  if dirty_count > 0 then
    color = "0xfff9e2af" -- Yellow when dirty
    if dirty_count > 5 then
      color = "0xfff38ba8" -- Red when very dirty
    end
  end

  return {
    icon = {
      string = icon,
      color = color,
    },
    label = {
      string = dirty_count > 0 and tostring(dirty_count) or "",
      color = color,
    },
    popup = {
      align = "left",
    },
  }
end

-- Open workspace overview
function workspace.open_overview()
  os.execute("syshelp workspace &")
end

-- Jump to project
function workspace.jump_to_project(project_name)
  for _, proj in ipairs(KEY_PROJECTS) do
    if proj.name == project_name then
      os.execute(string.format("open -a Terminal '%s/%s'", WS_ROOT, proj.path))
      return true
    end
  end
  return false
end

-- Clear caches
function workspace.clear_cache()
  os.execute("rm -f " .. DIRTY_CACHE)
  os.execute("rm -f " .. PROJECTS_CACHE)
  os.execute("syshelp wsrefresh")
  return true
end

return workspace
