local whichkey = {}

local sbar = require("sketchybar")
local json = require("json")
local menu_renderer = require("menu_renderer")

local HOME = os.getenv("HOME") or ""

local function load_json(path)
  if not path then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  if not contents then return nil end
  local ok, data = pcall(json.decode, contents)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

local function trim(str)
  if not str then return "" end
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function expand_path(path)
  if not path or path == "" then return nil end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  elseif path:sub(1, 1) == "/" then
    return path
  else
    return HOME .. "/" .. path
  end
end

local function shell_read(cmd)
  local handle = io.popen(cmd)
  if not handle then return "" end
  local result = handle:read("*a") or ""
  handle:close()
  return result
end

local function repo_status(repo)
  local path = expand_path(repo.path)
  if not path then return nil end
  local branch_output = shell_read(string.format("cd %q && git rev-parse --abbrev-ref HEAD 2>/dev/null", path))
  local dirty_output = shell_read(string.format("cd %q && git status --short 2>/dev/null", path))
  local branch = trim(branch_output)
  if branch == "" then branch = "—" end
  local dirty = trim(dirty_output) ~= ""
  return { branch = branch, dirty = dirty, path = path }
end

function whichkey.setup(_ctx)
  -- WhichKey HUD removed: delegate to syshelp-panel toggle on whichkey_toggle event.
  local base_item = "whichkey_stub"
  sbar.add("item", base_item, {
    position = "left",
    drawing = false,
    script = [[if [ "$SENDER" = "whichkey_toggle" ]; then ~/.local/bin/syshelp-panel toggle; fi]]
  })
  sbar.exec(string.format("sleep 0.1; sketchybar --subscribe %s whichkey_toggle", base_item))
end

return whichkey
