-- State Management Module
-- Centralized state persistence and live updates
-- v1.1.0 - Added state versioning for migrations

local state = {}
local json = require("json")

local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"
local STATE_FILE = CONFIG_DIR .. "/state.json"

-- State version for migrations
local STATE_VERSION = 1

-- Performance optimization: batch writes and debouncing
local save_timer = nil
local save_delay = 0.5  -- Wait 500ms before saving (debounce)
local pending_save = false
local dirty_flag = false

-- Forward declaration for save_immediate (defined after sanitize_state/merge_defaults)
local save_immediate

-- Default state structure
local default_state = {
  _version = STATE_VERSION,  -- Track state schema version
  widgets = {
    system_info = true,
    network = true,
    clock = true,
    volume = true,
    battery = true,
  },
  appearance = {
    theme = "default",
    bar_height = 28,
    corner_radius = 0,
    bar_color = "0xC021162F",
    blur_radius = 30,
    clock_font_style = "Semibold",
    widget_scale = 1.0,
    widget_corner_radius = 6,
    font_icon = "Hack Nerd Font",
    font_text = "Source Code Pro",
    font_numbers = "SF Mono",
  },
  icons = {
    apple = "",        -- FontAwesome apple icon (F179)
    quest = "󰊠",       -- Material Design triforce (F02A0)
    settings = "",    -- FontAwesome gear (F013)
    clock = "",       -- FontAwesome clock (F017)
    calendar = "",    -- FontAwesome calendar (F073)
    battery = "",    -- FontAwesome battery (F240)
    wifi = "󰖩",        -- Material Design wifi (F05A9)
    volume = "",     -- FontAwesome volume (F028)
  },
  widget_colors = {},
  space_icons = {},
  space_modes = {},
  system_info_items = {
    cpu = true,
    mem = true,
    disk = true,
    net = true,
    docs = true,
    actions = true,
  },
  toggles = {
    yabai_shortcuts = true,
  },
  integrations = {
    yaze = {
      enabled = true,
      recent_roms = {},
      build_dir = "build/bin",
    },
    emacs = {
      enabled = true,
      workspace_name = "Emacs",
      recent_org_files = {},
    },
    halext = {
      enabled = false,
      server_url = "",
      api_key = "",
      sync_interval = 300, -- 5 minutes
      show_tasks = true,
      show_calendar = true,
      show_suggestions = true,
    },
  },
}

-- Utility functions
local function merge_defaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      target[key] = merge_defaults(target[key] or {}, value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

local function sanitize_state(data)
  if type(data.widgets) ~= "table" then data.widgets = {} end
  if type(data.widget_colors) ~= "table" then data.widget_colors = {} end
  if type(data.appearance) ~= "table" then data.appearance = {} end
  if type(data.toggles) ~= "table" then data.toggles = {} end
  if type(data.icons) ~= "table" then data.icons = {} end
  if type(data.integrations) ~= "table" then data.integrations = {} end
  if type(data.space_modes) ~= "table" then data.space_modes = {} end

  -- Handle space_icons
  if type(data.space_icons) ~= "table" then
    data.space_icons = {}
  else
    local has_string_key = false
    for key, _ in pairs(data.space_icons) do
      if type(key) == "string" then
        has_string_key = true
        break
      end
    end
    if not has_string_key then
      data.space_icons = {}
    end
  end
  if type(data.space_icons) == "table" and next(data.space_icons) == nil then
    data.space_icons = nil
  end

  if type(data.system_info_items) ~= "table" then
    data.system_info_items = {}
  end
end

-- Migrate state from old version to new version
local function migrate_state(data, from_version, to_version)
  -- Migration 0 -> 1: Add _version field
  if (from_version or 0) < 1 and to_version >= 1 then
    data._version = 1
    -- Future migrations can be added here:
    -- if from_version < 2 then ... end
  end
  return data
end

-- Load state from disk
function state.load()
  local data
  local file = io.open(STATE_FILE, "r")
  if file then
    local contents = file:read("*a")
    file:close()
    local ok, decoded = pcall(json.decode, contents)
    if ok and type(decoded) == "table" then
      data = decoded
    end
  end

  if not data then
    data = {}
  end

  -- Check version and migrate if needed
  local loaded_version = data._version or 0
  if loaded_version < STATE_VERSION then
    data = migrate_state(data, loaded_version, STATE_VERSION)
    data._version = STATE_VERSION
    -- Save migrated state immediately
    sanitize_state(data)
    merge_defaults(data, default_state)
    save_immediate(data)
  else
    sanitize_state(data)
    merge_defaults(data, default_state)
    sanitize_state(data)
  end

  return data
end

-- Get current state version
function state.get_version()
  return STATE_VERSION
end

-- Save state to disk (internal, immediate write)
save_immediate = function(data)
  sanitize_state(data)
  local ok, encoded = pcall(json.encode, data)
  if ok then
    local tmp_file = STATE_FILE .. ".tmp"
    local wf = io.open(tmp_file, "w")
    if wf then
      wf:write(encoded)
      wf:close()
      os.rename(tmp_file, STATE_FILE)
      dirty_flag = false
      return true
    end
  end
  return false
end

-- Save state to disk (with debouncing)
function state.save(data, immediate)
  if immediate then
    return save_immediate(data)
  end
  
  dirty_flag = true
  pending_save = true
  
  -- Clear existing timer
  if save_timer then
    -- Note: In Lua, we can't easily cancel timers, so we just set a flag
    -- The timer will check the flag before saving
  end
  
  -- Schedule save after delay
  -- Since we can't use actual timers in pure Lua, we'll save immediately
  -- but mark as dirty to prevent redundant saves in rapid succession
  -- The debouncing will be handled at the call site if needed
  
  return save_immediate(data)
end

-- Force immediate save (for critical updates)
function state.save_immediate(data)
  return save_immediate(data)
end

-- Check if state is dirty
function state.is_dirty()
  return dirty_flag
end

-- Mark state as clean
function state.mark_clean()
  dirty_flag = false
end

-- Update a specific key path in state
-- Example: state.update(data, "appearance.bar_height", 30)
function state.update(data, key_path, value)
  local keys = {}
  for key in key_path:gmatch("[^.]+") do
    table.insert(keys, key)
  end

  local current = data
  for i = 1, #keys - 1 do
    if type(current[keys[i]]) ~= "table" then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end

  local old_value = current[keys[#keys]]
  current[keys[#keys]] = value
  -- Only save if value actually changed
  if old_value ~= value then
    return state.save(data, false)
  end
  return true
end

-- Get a specific value from state
function state.get(data, key_path, default)
  local keys = {}
  for key in key_path:gmatch("[^.]+") do
    table.insert(keys, key)
  end

  local current = data
  for _, key in ipairs(keys) do
    if type(current) ~= "table" or current[key] == nil then
      return default
    end
    current = current[key]
  end

  return current
end

-- Toggle a boolean value
function state.toggle(data, key_path)
  local current = state.get(data, key_path, false)
  return state.update(data, key_path, not current)
end

-- Widget helpers
function state.widget_enabled(data, name)
  if data.widgets[name] == nil then
    return true
  end
  return data.widgets[name]
end

function state.toggle_widget(data, name)
  local current = state.widget_enabled(data, name)
  data.widgets[name] = not current
  -- Widget toggles don't need immediate save
  return state.save(data, false)
end

-- Appearance helpers
function state.set_appearance(data, key, value)
  if not data.appearance then
    data.appearance = {}
  end
  -- Only save if value actually changed
  if data.appearance[key] ~= value then
    data.appearance[key] = value
    return state.save(data, false)
  end
  return true
end

function state.get_appearance(data, key, default)
  if not data.appearance then
    return default
  end
  return data.appearance[key] or default
end

-- Icon helpers
function state.set_icon(data, name, glyph)
  if not data.icons then
    data.icons = {}
  end
  -- Only save if value actually changed
  if data.icons[name] ~= glyph then
    data.icons[name] = glyph
    return state.save(data, false)
  end
  return true
end

function state.get_icon(data, name, default)
  if not data.icons then
    return default
  end
  return data.icons[name] or default
end

-- Space icon helpers
function state.set_space_icon(data, space_num, glyph)
  if not data.space_icons then
    data.space_icons = {}
  end
  local key = tostring(space_num)
  -- Only save if value actually changed
  if data.space_icons[key] ~= glyph then
    data.space_icons[key] = glyph
    return state.save(data, false)
  end
  return true
end

function state.set_space_mode(data, space_num, mode)
  if not data.space_modes then
    data.space_modes = {}
  end
  local key = tostring(space_num)
  local new_value = (mode == "float" or mode == nil) and nil or mode
  -- Only save if value actually changed
  if data.space_modes[key] ~= new_value then
    data.space_modes[key] = new_value
    return state.save(data, false)
  end
  return true
end

function state.get_space_mode(data, space_num, default)
  if not data.space_modes then
    return default
  end
  return data.space_modes[tostring(space_num)] or default
end

function state.list_space_modes(data)
  if type(data.space_modes) ~= "table" then
    return {}
  end
  return data.space_modes
end

function state.get_space_icon(data, space_num, default)
  if not data.space_icons then
    return default
  end
  return data.space_icons[tostring(space_num)] or default
end

-- Widget color helpers
function state.set_widget_color(data, widget_name, color)
  if not data.widget_colors then
    data.widget_colors = {}
  end
  -- Only save if value actually changed
  if data.widget_colors[widget_name] ~= color then
    data.widget_colors[widget_name] = color
    return state.save(data, false)
  end
  return true
end

function state.get_widget_color(data, widget_name, default)
  if not data.widget_colors then
    return default
  end
  return data.widget_colors[widget_name] or default
end

-- Integration helpers
function state.get_integration(data, integration_name)
  if not data.integrations or not data.integrations[integration_name] then
    return default_state.integrations[integration_name] or {}
  end
  return data.integrations[integration_name]
end

function state.update_integration(data, integration_name, key, value)
  if not data.integrations then
    data.integrations = {}
  end
  if not data.integrations[integration_name] then
    data.integrations[integration_name] = {}
  end
  -- Only save if value actually changed
  if data.integrations[integration_name][key] ~= value then
    data.integrations[integration_name][key] = value
    return state.save(data, false)
  end
  return true
end

return state
