-- binary_resolver.lua - Locate SketchyBar, Yabai, and compiled helper binaries.
-- Extracted from main.lua to centralise binary detection.

local shell_utils = require("shell_utils")

local M = {}

--- Locate the sketchybar binary.
function M.resolve_sketchybar_bin()
  local env_bin = os.getenv("SKETCHYBAR_BIN")
  if env_bin and env_bin ~= "" then
    return env_bin
  end
  local handle = io.popen("command -v sketchybar 2>/dev/null")
  if handle then
    local result = handle:read("*a") or ""
    handle:close()
    result = result:gsub("%s+$", "")
    if result ~= "" then
      return result
    end
  end
  local candidates = {
    "/opt/homebrew/opt/sketchybar/bin/sketchybar",
    "/opt/homebrew/bin/sketchybar",
    "/usr/local/opt/sketchybar/bin/sketchybar",
    "/usr/local/bin/sketchybar",
  }
  for _, candidate in ipairs(candidates) do
    if shell_utils.file_exists(candidate) then
      return candidate
    end
  end
  return "sketchybar"
end

--- Locate the yabai binary (returns nil when not found).
function M.resolve_yabai_bin()
  local env_bin = os.getenv("YABAI_BIN")
  if env_bin and env_bin ~= "" then
    return env_bin
  end
  local handle = io.popen("command -v yabai 2>/dev/null")
  if handle then
    local result = handle:read("*a") or ""
    handle:close()
    result = result:gsub("%s+$", "")
    if result ~= "" then
      return result
    end
  end
  local candidates = {
    "/opt/homebrew/bin/yabai",
    "/usr/local/bin/yabai",
  }
  for _, candidate in ipairs(candidates) do
    if shell_utils.file_exists(candidate) then
      return candidate
    end
  end
  return nil
end

--- Resolve a compiled C helper binary.
--- Looks in build/bin/ first (CMake output), then bin/ (installed location).
--- Falls back to the Lua/shell equivalent when running in Lua-only mode.
function M.compiled_script(config_dir, lua_only, binary_name, fallback)
  if lua_only then
    return fallback
  end
  -- Prefer build output, then installed bin/
  local search_dirs = {
    config_dir .. "/build/bin",
    config_dir .. "/bin",
  }
  for _, dir in ipairs(search_dirs) do
    local path = string.format("%s/%s", dir, binary_name)
    if shell_utils.file_exists(path) then
      return path
    end
  end
  print("WARNING: Binary not found: " .. binary_name)
  return fallback
end

--- Check if yabai is currently running.
function M.yabai_running()
  local handle = io.popen("pgrep -x yabai >/dev/null 2>&1 && echo 1 || echo 0")
  if not handle then
    return false
  end
  local result = handle:read("*a") or ""
  handle:close()
  return result:match("1") ~= nil
end

--- Normalise window manager mode strings to a canonical form.
function M.normalize_window_manager_mode(mode)
  if not mode or mode == "" then
    return "auto"
  end
  mode = tostring(mode):lower()
  if mode == "off" or mode == "false" or mode == "none" or mode == "disable" or mode == "disabled" then
    return "disabled"
  end
  if mode == "optional" or mode == "opt" then
    return "optional"
  end
  if mode == "required" or mode == "require" or mode == "enabled" or mode == "enable" or mode == "on" then
    return "required"
  end
  return mode
end

--- Compute effective window-manager mode from env + state.
function M.resolve_window_manager_mode(state_module, state)
  local mode = os.getenv("BARISTA_WINDOW_MANAGER_MODE")
  if not mode or mode == "" then
    mode = state_module.get(state, "modes.window_manager", "auto")
  end
  return M.normalize_window_manager_mode(mode)
end

--- Determine whether the window manager should be active.
function M.compute_window_manager_enabled(mode, yabai_bin)
  local function yabai_avail()
    return yabai_bin ~= nil and yabai_bin ~= ""
  end
  if mode == "disabled" then
    return false
  end
  if mode == "optional" then
    return M.yabai_running()
  end
  if mode == "required" then
    if not yabai_avail() then
      print("Barista: window_manager=required but yabai not found in PATH")
    end
    return yabai_avail()
  end
  return yabai_avail()
end

return M
