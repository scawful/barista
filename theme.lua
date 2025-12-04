-- Theme loader with overrides
-- Priority: BARISTA_THEME env > state.json appearance.theme > default ("default")
-- Optional override file: ~/.config/sketchybar/themes/theme.local.lua

local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"
local DEFAULT_THEME = "default"

-- Make sure we can load the bundled JSON helper before main.lua adjusts package.path
package.path = package.path .. ";" .. CONFIG_DIR .. "/helpers/lib/?.lua"

local function load_theme(name)
  if not name or name == "" then
    return nil
  end
  local ok, mod = pcall(require, "themes." .. name)
  if ok and type(mod) == "table" then
    return mod
  end
  return nil
end

local function read_state_theme()
  local state_file = CONFIG_DIR .. "/state.json"
  local fh = io.open(state_file, "r")
  if not fh then return nil end
  local contents = fh:read("*a")
  fh:close()

  local ok, json = pcall(require, "json")
  if not ok or type(json) ~= "table" or type(json.decode) ~= "function" then
    return nil
  end

  local ok_decode, data = pcall(json.decode, contents)
  if ok_decode and type(data) == "table" and
     type(data.appearance) == "table" and
     type(data.appearance.theme) == "string" then
    return data.appearance.theme
  end
  return nil
end

local function apply_overrides(base, overrides)
  if type(base) ~= "table" or type(overrides) ~= "table" then
    return base
  end
  for k, v in pairs(overrides) do
    base[k] = v
  end
  return base
end

local theme_name = os.getenv("BARISTA_THEME") or read_state_theme() or DEFAULT_THEME
local theme = load_theme(theme_name) or load_theme(DEFAULT_THEME) or {}

-- Optional user override file
local override_file = CONFIG_DIR .. "/themes/theme.local.lua"
local ok_override, override_table = pcall(dofile, override_file)
if ok_override and type(override_table) == "table" then
  theme = apply_overrides(theme, override_table)
end

return theme
