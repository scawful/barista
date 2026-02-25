#!/usr/bin/env lua
-- Validate theme files for required and optional keys (see docs/features/THEMES.md).
-- Usage: lua scripts/validate_theme.lua [theme_name]
--   With no args, validates all .lua files in themes/.
--   CONFIG_DIR: BARISTA_CONFIG_DIR or directory containing this script's repo (parent of scripts/).

local function get_config_dir()
  local env = os.getenv("BARISTA_CONFIG_DIR")
  if env and env ~= "" then return env end
  local script = arg[0] or ""
  if script:match("^/") then
    return script:gsub("/scripts/validate_theme.lua$", ""):gsub("/scripts/.*", "")
  end
  return (io.popen("pwd"):read("*a") or ""):gsub("%s+$", "")
end
local CONFIG_DIR = get_config_dir()
package.path = package.path .. ";" .. CONFIG_DIR .. "/?.lua"

local REQUIRED = {
  "bar",
  "WHITE",
  "DARK_WHITE",
  "BG_PRI_COLR",
  "BG_SEC_COLR",
}
local REQUIRED_BAR = { "bg" }
local OPTIONAL_WIDGET = { "clock", "volume", "battery" }

local function check_theme(name)
  local ok, mod = pcall(require, "themes." .. name)
  if not ok then
    io.stderr:write(string.format("validate_theme: failed to load theme %s: %s\n", name, tostring(mod)))
    return false
  end
  if type(mod) ~= "table" then
    io.stderr:write(string.format("validate_theme: theme %s did not return a table\n", name))
    return false
  end

  local valid = true
  for _, key in ipairs(REQUIRED) do
    if mod[key] == nil then
      io.stderr:write(string.format("validate_theme: %s missing required key %s\n", name, key))
      valid = false
    end
  end
  if type(mod.bar) == "table" then
    for _, key in ipairs(REQUIRED_BAR) do
      if mod.bar[key] == nil then
        io.stderr:write(string.format("validate_theme: %s missing required key bar.%s\n", name, key))
        valid = false
      end
    end
  elseif mod.bar == nil then
    io.stderr:write(string.format("validate_theme: %s missing required key bar\n", name))
    valid = false
  end

  for _, key in ipairs(OPTIONAL_WIDGET) do
    if mod[key] == nil then
      io.stdout:write(string.format("validate_theme: %s optional key %s not set (bar will use BG_SEC_COLR)\n", name, key))
    end
  end
  return valid
end

local function list_themes()
  local dir = CONFIG_DIR .. "/themes"
  local fh = io.popen("ls " .. dir .. " 2>/dev/null | grep -E '\\.lua$' | sed 's/\\.lua$//'")
  if not fh then return {} end
  local out = fh:read("*a")
  fh:close()
  local list = {}
  for name in (out or ""):gmatch("%S+") do
    if name ~= "theme.local" then
      list[#list + 1] = name
    end
  end
  return list
end

local main = function()
  local themes_to_check = {}
  if arg[1] and arg[1] ~= "" then
    themes_to_check[1] = arg[1]:gsub("%.lua$", "")
  else
    themes_to_check = list_themes()
  end

  if #themes_to_check == 0 then
    io.stderr:write("validate_theme: no themes to validate (pass a name or ensure themes/*.lua exist)\n")
    os.exit(1)
  end

  local all_ok = true
  for _, name in ipairs(themes_to_check) do
    if not check_theme(name) then
      all_ok = false
    end
  end
  os.exit(all_ok and 0 or 1)
end

main()
