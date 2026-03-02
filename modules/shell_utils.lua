-- shell_utils.lua - Shell execution helpers for Barista
-- Extracted from main.lua to reduce monolith size.

-- Lazy-load sketchybar C module (only available inside SketchyBar runtime).
-- This allows the module to be require()'d in test environments.
local _sbar = nil
local function get_sbar()
  if not _sbar then
    local ok, mod = pcall(require, "sketchybar")
    if ok then _sbar = mod
    else error("shell_utils: sketchybar module not available (are you inside the SketchyBar runtime?)", 2) end
  end
  return _sbar
end

local M = {}

--- Quote a value for safe shell interpolation.
function M.shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

--- Execute a shell command via sbar.exec with a proper PATH.
function M.shell_exec(cmd)
  local base_path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
  local env_path = os.getenv("PATH")
  if env_path and env_path ~= "" then
    base_path = base_path .. ":" .. env_path
  end
  get_sbar().exec(string.format("env PATH=%s bash -lc %s", M.shell_quote(base_path), M.shell_quote(cmd)))
end

--- Execute a sketchybar CLI command.
function M.sketchybar_cli(sketchybar_bin, cmd)
  if not cmd or cmd == "" then
    return
  end
  M.shell_exec(string.format("%s %s", sketchybar_bin, cmd))
end

--- Build a shell command to open a path in Finder / default handler.
function M.open_path(path)
  return string.format("open %q", path)
end

--- Build a shell command to open a URL.
function M.open_url(url)
  return string.format("open %q", url)
end

--- Build a shell command that calls a script with quoted arguments.
function M.call_script(script_path, ...)
  if not script_path or script_path == "" then
    return ""
  end
  local cmd = string.format("bash %q", script_path)
  local args = { ... }
  if #args > 0 then
    local parts = {}
    for _, arg in ipairs(args) do
      table.insert(parts, string.format("%q", tostring(arg)))
    end
    cmd = string.format("%s %s", cmd, table.concat(parts, " "))
  end
  return cmd
end

--- Check if a file exists at the given path.
function M.file_exists(path)
  if not path or path == "" then
    return false
  end
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

--- Build an "env KEY=VAL …" prefix string from a table.
--- Keys are sorted for deterministic output.
function M.env_prefix(vars)
  local keys = {}
  for key, value in pairs(vars or {}) do
    if type(value) == "string" and value ~= "" then
      table.insert(keys, key)
    end
  end
  if #keys == 0 then
    return ""
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, string.format("%s=%q", key, vars[key]))
  end
  return "env " .. table.concat(parts, " ") .. " "
end

--- Check if a command is available in PATH.
function M.command_available(name)
  if not name or name == "" then
    return false
  end
  local handle = io.popen(string.format("command -v %q 2>/dev/null", name))
  if not handle then
    return false
  end
  local result = handle:read("*a") or ""
  handle:close()
  return result:gsub("%s+$", "") ~= ""
end

--- Check if a process is running by name.
function M.check_service(name)
  if not name or name == "" then
    return false
  end
  local handle = io.popen(string.format("pgrep -x %s >/dev/null 2>&1 && echo 1 || echo 0", name))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

return M
