-- Component Switcher Module
-- Allows runtime switching between C and Lua implementations
-- Provides performance comparison and fallback mechanisms

local component_switcher = {}

local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"
local SETTINGS_FILE = CONFIG_DIR .. "/component_settings.json"

-- Component types
component_switcher.ICON_MANAGER = "icon_manager"
component_switcher.STATE_MANAGER = "state_manager"
component_switcher.WIDGET_MANAGER = "widget_manager"
component_switcher.MENU_RENDERER = "menu_renderer"

-- Implementation types
component_switcher.C_IMPL = "c"
component_switcher.LUA_IMPL = "lua"
component_switcher.AUTO = "auto"

-- Default settings
local default_settings = {
  mode = "auto",  -- auto, c, lua, hybrid
  components = {
    icon_manager = {
      implementation = "auto",
      fallback = "lua",
      enabled = true,
    },
    state_manager = {
      implementation = "auto",
      fallback = "lua",
      enabled = true,
    },
    widget_manager = {
      implementation = "auto",
      fallback = "lua",
      enabled = true,
    },
    menu_renderer = {
      implementation = "auto",
      fallback = "lua",
      enabled = true,
    },
  },
  performance_tracking = true,
  auto_fallback = true,  -- Automatically fallback to Lua if C fails
  logging = true,
}

-- Current settings
local settings = nil

-- Performance tracking
local perf_stats = {
  icon_manager = {c_calls = 0, c_time = 0, lua_calls = 0, lua_time = 0},
  state_manager = {c_calls = 0, c_time = 0, lua_calls = 0, lua_time = 0},
  widget_manager = {c_calls = 0, c_time = 0, lua_calls = 0, lua_time = 0},
  menu_renderer = {c_calls = 0, c_time = 0, lua_calls = 0, lua_time = 0},
}

-- Load settings
local function load_settings()
  local json = require("json")
  local file = io.open(SETTINGS_FILE, "r")
  if file then
    local contents = file:read("*a")
    file:close()
    local ok, data = pcall(json.decode, contents)
    if ok and type(data) == "table" then
      settings = data
      return
    end
  end

  -- Use defaults
  settings = default_settings
end

-- Save settings
local function save_settings()
  local json = require("json")
  local ok, encoded = pcall(json.encode, settings)
  if ok then
    local file = io.open(SETTINGS_FILE, "w")
    if file then
      file:write(encoded)
      file:close()
      return true
    end
  end
  return false
end

-- Check if C component is available
local function c_component_available(component)
  local path = CONFIG_DIR .. "/bin/" .. component
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- Log message
local function log(component, message)
  if settings.logging then
    print(string.format("[ComponentSwitcher:%s] %s", component, message))
  end
end

-- Track performance
local function track_perf(component, impl, duration)
  if not settings.performance_tracking then
    return
  end

  if impl == "c" then
    perf_stats[component].c_calls = perf_stats[component].c_calls + 1
    perf_stats[component].c_time = perf_stats[component].c_time + duration
  else
    perf_stats[component].lua_calls = perf_stats[component].lua_calls + 1
    perf_stats[component].lua_time = perf_stats[component].lua_time + duration
  end
end

-- Get implementation to use
local function get_implementation(component)
  if not settings then
    load_settings()
  end

  local comp_settings = settings.components[component]
  if not comp_settings or not comp_settings.enabled then
    return "lua"
  end

  local impl = comp_settings.implementation

  -- If auto, check C availability
  if impl == "auto" then
    if c_component_available(component) then
      return "c"
    else
      log(component, "C implementation not available, using Lua")
      return "lua"
    end
  end

  -- If specific implementation requested, validate it
  if impl == "c" then
    if c_component_available(component) then
      return "c"
    elseif settings.auto_fallback then
      log(component, "C implementation requested but not available, falling back to Lua")
      return comp_settings.fallback or "lua"
    else
      error(string.format("C implementation of %s not available and auto_fallback disabled", component))
    end
  end

  return impl
end

-- Execute C component
local function exec_c(component, ...)
  local args = {...}
  local cmd = CONFIG_DIR .. "/bin/" .. component
  for _, arg in ipairs(args) do
    cmd = cmd .. " " .. string.format("%q", tostring(arg))
  end

  local start_time = os.clock()
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute C component"
  end

  local result = handle:read("*a")
  handle:close()
  local duration = os.clock() - start_time

  track_perf(component, "c", duration)

  return result
end

-- Execute Lua component
local function exec_lua(component, func, ...)
  local start_time = os.clock()
  local result = func(...)
  local duration = os.clock() - start_time

  track_perf(component, "lua", duration)

  return result
end

-- Initialize component switcher
function component_switcher.init()
  load_settings()

  log("system", "Component switcher initialized")
  log("system", string.format("Mode: %s", settings.mode))

  -- Check C component availability
  local available_components = {}
  for component, _ in pairs(settings.components) do
    if c_component_available(component) then
      table.insert(available_components, component)
      log(component, "C implementation available")
    else
      log(component, "C implementation not available, will use Lua")
    end
  end

  return true
end

-- Set global mode
function component_switcher.set_mode(mode)
  if mode ~= "auto" and mode ~= "c" and mode ~= "lua" and mode ~= "hybrid" then
    error("Invalid mode: " .. mode)
  end

  settings.mode = mode

  -- Update all components
  for component, comp_settings in pairs(settings.components) do
    if mode == "auto" then
      comp_settings.implementation = "auto"
    else
      comp_settings.implementation = mode
    end
  end

  save_settings()
  log("system", "Mode changed to: " .. mode)
end

-- Set component implementation
function component_switcher.set_component(component, impl)
  if not settings.components[component] then
    error("Unknown component: " .. component)
  end

  settings.components[component].implementation = impl
  save_settings()
  log(component, "Implementation changed to: " .. impl)
end

-- Get component implementation
function component_switcher.get_component_impl(component)
  return get_implementation(component)
end

-- Execute with auto-selection
function component_switcher.execute(component, c_func, lua_func, ...)
  local impl = get_implementation(component)

  if impl == "c" then
    local ok, result = pcall(exec_c, component, ...)
    if ok then
      return result
    else
      if settings.auto_fallback then
        log(component, "C implementation failed, falling back to Lua: " .. tostring(result))
        return exec_lua(component, lua_func, ...)
      else
        error(string.format("C implementation of %s failed: %s", component, result))
      end
    end
  else
    return exec_lua(component, lua_func, ...)
  end
end

-- Get performance statistics
function component_switcher.get_stats()
  local stats = {}

  for component, perf in pairs(perf_stats) do
    stats[component] = {
      c_calls = perf.c_calls,
      c_avg_time = perf.c_calls > 0 and (perf.c_time / perf.c_calls) or 0,
      c_total_time = perf.c_time,
      lua_calls = perf.lua_calls,
      lua_avg_time = perf.lua_calls > 0 and (perf.lua_time / perf.lua_calls) or 0,
      lua_total_time = perf.lua_time,
    }

    -- Calculate speedup
    if stats[component].lua_avg_time > 0 and stats[component].c_avg_time > 0 then
      stats[component].speedup = stats[component].lua_avg_time / stats[component].c_avg_time
    else
      stats[component].speedup = 0
    end
  end

  return stats
end

-- Print performance report
function component_switcher.print_report()
  local stats = component_switcher.get_stats()

  print("\n=== Component Switcher Performance Report ===\n")

  for component, stat in pairs(stats) do
    print(string.format("%s:", component))
    print(string.format("  C:   %d calls, avg %.3fms, total %.3fms",
      stat.c_calls, stat.c_avg_time * 1000, stat.c_total_time * 1000))
    print(string.format("  Lua: %d calls, avg %.3fms, total %.3fms",
      stat.lua_calls, stat.lua_avg_time * 1000, stat.lua_total_time * 1000))
    if stat.speedup > 0 then
      print(string.format("  Speedup: %.2fx faster with C", stat.speedup))
    end
    print("")
  end
end

-- Reset performance statistics
function component_switcher.reset_stats()
  for component, _ in pairs(perf_stats) do
    perf_stats[component] = {c_calls = 0, c_time = 0, lua_calls = 0, lua_time = 0}
  end
  log("system", "Performance statistics reset")
end

-- Get current settings
function component_switcher.get_settings()
  if not settings then
    load_settings()
  end
  return settings
end

-- Enable performance tracking
function component_switcher.enable_tracking(enable)
  settings.performance_tracking = enable
  save_settings()
  log("system", "Performance tracking " .. (enable and "enabled" or "disabled"))
end

-- Enable logging
function component_switcher.enable_logging(enable)
  settings.logging = enable
  save_settings()
end

-- Check component health
function component_switcher.health_check()
  local health = {
    healthy = true,
    issues = {},
    components = {},
  }

  for component, comp_settings in pairs(settings.components) do
    local comp_health = {
      enabled = comp_settings.enabled,
      implementation = comp_settings.implementation,
      c_available = c_component_available(component),
      status = "ok",
    }

    if comp_settings.enabled and comp_settings.implementation == "c" then
      if not comp_health.c_available then
        comp_health.status = "error"
        table.insert(health.issues, string.format("%s: C implementation not available", component))
        health.healthy = false
      end
    end

    health.components[component] = comp_health
  end

  return health
end

return component_switcher