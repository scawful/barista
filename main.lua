-- SketchyBar Configuration
-- Modular, modern macOS status bar with Yabai integration

local sbar = require("sketchybar")
local theme = require("theme")
local utf8 = require("utf8")
local unpack = table.unpack or _G.unpack

-- Load modules
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/integrations/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/?.lua"

-- Core modules
local state_module   = require("state")
local profile_module = require("profile")
local bar_config     = require("bar_config")
local icons_module   = require("icons")
local icon_manager   = require("icon_manager")
local shortcuts      = require("shortcuts")
local widgets_module = require("widgets")
local menu_module    = require("menu")
local yaze_module    = require("yaze")
local oracle_module  = require("oracle")
local emacs_module   = require("emacs")

-- Extracted utility modules
local shell_utils      = require("shell_utils")
local paths_module     = require("paths")
local binary_resolver  = require("binary_resolver")

-- Initialize component switcher for C/Lua hybrid architecture
local component_switcher = require("component_switcher")

-- Runtime backend selection: environment overrides state, which lets managed
-- machines persist a Lua-only fallback without depending on shell env.
local runtime_backend = binary_resolver.resolve_runtime_backend(
  binary_resolver.read_runtime_backend_from_state(CONFIG_DIR)
)
local LUA_ONLY = runtime_backend == "lua"
local c_bridge = nil

if not LUA_ONLY then
  local ok, mod = pcall(require, "c_bridge")
  if ok then
    c_bridge = mod
    if c_bridge.check_components then
      local status = c_bridge.check_components()
      if status and not status.all_present then
        print(string.format("Barista: missing C helpers (%s); switching to Lua-only fallback", table.concat(status.missing, ", ")))
        LUA_ONLY = true
      end
    end
  else
    print("Barista: c_bridge unavailable; switching to Lua-only fallback")
    LUA_ONLY = true
  end
end

component_switcher.init()
component_switcher.set_mode(LUA_ONLY and "lua" or "auto")

if not LUA_ONLY and c_bridge then
  c_bridge.init()
else
  c_bridge = c_bridge or { init = function() end }
  if runtime_backend == "lua" then
    print("Barista: runtime_backend=lua; running in Lua-only mode")
  else
    print("Barista: running in Lua-only mode (no compiled helpers)")
  end
end

-- Import existing icons into icon_manager for backwards compatibility
icon_manager.import_from_module(icons_module)

-- Resolve paths
local PLUGIN_DIR = CONFIG_DIR .. "/plugins"
local EVENT_DIR  = CONFIG_DIR .. "/helpers/event_providers"

-- Load state and profile
local state = state_module.load()
local profile_name = profile_module.get_selected_profile(state)
local user_profile = profile_module.load(profile_name)

if user_profile then
  state = profile_module.merge_config(state, user_profile)
  print("Loaded profile: " .. user_profile.name)
end

-- Load user configuration overrides if they exist
local user_config_path = CONFIG_DIR .. "/barista_config.lua"
local user_config_chunk = loadfile(user_config_path)
if user_config_chunk then
  local ok, user_config = pcall(user_config_chunk)
  if ok and type(user_config) == "table" then
    print("Applying user configuration from barista_config.lua")
    local function merge_tables(target, source)
      for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
          merge_tables(target[k], v)
        else
          target[k] = v
        end
      end
    end
    merge_tables(state, user_config)
  elseif not ok then
    print("Warning: Error executing barista_config.lua: " .. tostring(user_config))
  end
end

-- Resolve directories and binaries
local CODE_DIR    = paths_module.resolve_code_dir(state)
local SCRIPTS_DIR = paths_module.resolve_scripts_dir(CONFIG_DIR, state)

local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()
local YABAI_BIN      = binary_resolver.resolve_yabai_bin()

local POST_CONFIG_DELAY = 1.0
local NET_INTERFACE = os.getenv("SKETCHYBAR_NET_INTERFACE") or "en0"

-- Convenience wrappers that close over resolved state
local function compiled_script(binary_name, fallback)
  return binary_resolver.compiled_script(CONFIG_DIR, LUA_ONLY, binary_name, fallback)
end

local HOVER_SCRIPT         = compiled_script("popup_hover",    PLUGIN_DIR .. "/popup_hover.sh")
local POPUP_ANCHOR_SCRIPT  = compiled_script("popup_anchor",   PLUGIN_DIR .. "/popup_anchor.sh")
local SUBMENU_HOVER_SCRIPT = compiled_script("submenu_hover",  PLUGIN_DIR .. "/submenu_hover.sh")
local POPUP_MANAGER_SCRIPT = compiled_script("popup_manager",  PLUGIN_DIR .. "/popup_manager.sh")
local POPUP_GUARD_SCRIPT   = compiled_script("popup_guard",    PLUGIN_DIR .. "/popup_guard.sh")

-- Yabai availability (cached)
local yabai_available_cache = nil
local function yabai_available()
  if yabai_available_cache == nil then
    if not YABAI_BIN or YABAI_BIN == "" then
      YABAI_BIN = binary_resolver.resolve_yabai_bin()
    end
    yabai_available_cache = (YABAI_BIN ~= nil and YABAI_BIN ~= "")
  end
  return yabai_available_cache
end

local WINDOW_MANAGER_MODE = binary_resolver.resolve_window_manager_mode(state_module, state)
local WINDOW_MANAGER_ENABLED = binary_resolver.compute_window_manager_enabled(WINDOW_MANAGER_MODE, YABAI_BIN)

-- Icon helpers
local function safe_icon(value)
  if type(value) ~= "string" then return nil end
  local ok = pcall(function() utf8.len(value) end)
  return ok and value or nil
end

local function icon_for(name, fallback)
  local from_state = safe_icon(state_module.get_icon(state, name, nil))
  if type(from_state) == "string" and from_state ~= "" then return from_state end
  local from_manager = safe_icon(icon_manager.get_char(name, nil))
  if type(from_manager) == "string" and from_manager ~= "" then return from_manager end
  local from_icons = safe_icon(icons_module.find(name))
  if type(from_icons) == "string" and from_icons ~= "" then return from_icons end
  return fallback or ""
end

_G.icon_for = icon_for

-- Integration flags
local function integration_enabled(name)
  local entry = state_module.get_integration(state, name)
  if type(entry) ~= "table" then return false end
  if entry.enabled == nil then return false end
  return entry.enabled ~= false
end

local yaze_enabled   = integration_enabled("yaze")
local oracle_enabled = integration_enabled("oracle")
local emacs_enabled  = integration_enabled("emacs")
local halext_enabled = integration_enabled("halext")
local halext_module  = halext_enabled and require("halext") or nil

local cortex_enabled = integration_enabled("cortex")
local cortex_module  = nil
if cortex_enabled then
  local ok, mod = pcall(require, "cortex")
  if ok then cortex_module = mod
  else print("Barista: cortex integration enabled but module not found") end
end

local janice_enabled = integration_enabled("janice")
local janice_module  = nil
if janice_enabled then
  local ok, mod = pcall(require, "janice")
  if ok then janice_module = mod
  else print("Barista: janice integration enabled but module not found") end
end

local premia_enabled = integration_enabled("premia")
local premia_module  = nil
if premia_enabled then
  local ok, mod = pcall(require, "premia")
  if ok then premia_module = mod
  else print("Barista: premia integration enabled but module not found") end
end

local control_center_enabled = integration_enabled("control_center") or cortex_enabled
local control_center_module = nil
if control_center_enabled then
  local ok, mod = pcall(require, "control_center")
  if ok then control_center_module = mod
  else print("Barista: control_center module not found, falling back to cortex") end
end

-- Popup toggle
local POPUP_TOGGLE_SCRIPT = SCRIPTS_DIR .. "/focus_display_and_toggle_popup.sh"
if not shell_utils.file_exists(POPUP_TOGGLE_SCRIPT) then
  local fallback = CONFIG_DIR .. "/scripts/focus_display_and_toggle_popup.sh"
  if shell_utils.file_exists(fallback) then POPUP_TOGGLE_SCRIPT = fallback end
end
local POPUP_TOGGLE_AVAILABLE = shell_utils.file_exists(POPUP_TOGGLE_SCRIPT)

local function popup_toggle_action(item_name)
  if POPUP_TOGGLE_AVAILABLE then
    return shell_utils.call_script(POPUP_TOGGLE_SCRIPT, item_name or "$NAME")
  end
  if item_name and item_name ~= "" then
    return string.format("%s --set %s popup.drawing=toggle", SKETCHYBAR_BIN, item_name)
  end
  return [[sketchybar -m --set $NAME popup.drawing=toggle]]
end

-- Hover helpers
local function attach_hover(name)
  shell_utils.shell_exec(string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited", POST_CONFIG_DELAY, SKETCHYBAR_BIN, name))
end

local function subscribe_popup_autoclose(name)
  shell_utils.shell_exec(string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited mouse.exited.global", POST_CONFIG_DELAY, SKETCHYBAR_BIN, name))
end

-- Spaces module
local spaces_module = require("spaces")
local space_fns = spaces_module.create(CONFIG_DIR, PLUGIN_DIR, SKETCHYBAR_BIN, YABAI_BIN, shell_utils.shell_exec, yabai_available)
local associated_displays = space_fns.get_associated_displays()
print("Associated displays target: " .. associated_displays)

-- Bar appearance from bar_config module
local bc = bar_config.compute(state, theme, state_module, associated_displays)

-- Build hover environment strings
local hover_script_cmd = shell_utils.env_prefix({
  POPUP_HOVER_COLOR            = tostring(bc.hover_color),
  POPUP_HOVER_BORDER_COLOR     = tostring(bc.hover_border_color),
  POPUP_HOVER_BORDER_WIDTH     = tostring(bc.hover_border_width),
  POPUP_HOVER_ANIMATION_CURVE  = tostring(bc.hover_animation_curve),
  POPUP_HOVER_ANIMATION_DURATION = tostring(bc.hover_animation_duration),
}) .. HOVER_SCRIPT

local submenu_hover_script_cmd = shell_utils.env_prefix({
  SUBMENU_HOVER_BG             = tostring(bc.submenu_hover_color),
  SUBMENU_IDLE_BG              = tostring(bc.submenu_idle_color),
  SUBMENU_CLOSE_DELAY          = tostring(bc.submenu_close_delay),
  SUBMENU_ANIMATION_CURVE      = tostring(bc.hover_animation_curve),
  SUBMENU_ANIMATION_DURATION   = tostring(bc.hover_animation_duration),
}) .. SUBMENU_HOVER_SCRIPT

-- Build paths / scripts tables
local profile_paths = profile_module.get_paths(user_profile)
local paths   = paths_module.build_paths_table(CONFIG_DIR, CODE_DIR, profile_paths)
local scripts = paths_module.build_scripts_table(CONFIG_DIR, SCRIPTS_DIR, PLUGIN_DIR)
local helpers = { help_center = CONFIG_DIR .. "/gui/bin/help_center" }

local integrations = {
  yaze   = yaze_enabled   and yaze_module   or nil,
  oracle = oracle_enabled and oracle_module or nil,
  emacs  = emacs_enabled  and emacs_module  or nil,
  halext = halext_enabled  and halext_module or nil,
  cortex = cortex_module,
  janice = janice_module,
  premia = premia_module,
  control_center = control_center_module,
}

-- Configure yaze integration
if yaze_module and type(yaze_module.configure) == "function" then
  yaze_module.configure({ repo_path = paths.yaze, rom_workflow_doc = paths.rom_doc })
end

-----------------------------------------------------------------------
-- Unified context – passed to menus, items_left, items_right, etc.
-----------------------------------------------------------------------
local barista_context = {
  -- Core
  sbar     = sbar,
  theme    = theme,
  settings = bc.settings,
  state    = state,

  -- Bar geometry
  widget_height        = bc.widget_height,
  widget_corner_radius = bc.widget_corner_radius,
  popup_background     = bc.popup_background,
  font_string          = bc.font_string,
  group_bg_color       = bc.group_bg_color,
  group_border_color   = bc.group_border_color,
  group_border_width   = bc.group_border_width,
  group_corner_radius  = bc.group_corner_radius,
  hover_color               = bc.hover_color,
  hover_animation_curve     = bc.hover_animation_curve,
  hover_animation_duration  = bc.hover_animation_duration,

  -- Scripts & hover
  HOVER_SCRIPT         = hover_script_cmd,
  SUBMENU_HOVER_SCRIPT = submenu_hover_script_cmd,
  hover_script_cmd     = hover_script_cmd,

  -- Helpers & shell
  shell_exec               = shell_utils.shell_exec,
  call_script              = shell_utils.call_script,
  open_path                = shell_utils.open_path,
  open_url                 = shell_utils.open_url,
  env_prefix               = shell_utils.env_prefix,
  attach_hover             = attach_hover,
  subscribe_popup_autoclose = subscribe_popup_autoclose,
  popup_toggle_action      = popup_toggle_action,
  popup_toggle_script      = POPUP_TOGGLE_AVAILABLE and POPUP_TOGGLE_SCRIPT or nil,

  -- Directories & binaries
  CONFIG_DIR      = CONFIG_DIR,
  PLUGIN_DIR      = PLUGIN_DIR,
  CODE_DIR        = CODE_DIR,
  SKETCHYBAR_BIN  = SKETCHYBAR_BIN,
  sketchybar_bin  = SKETCHYBAR_BIN,
  POST_CONFIG_DELAY = POST_CONFIG_DELAY,
  associated_displays = associated_displays,
  compiled_script = compiled_script,

  -- Paths, scripts, helpers, integrations
  paths       = paths,
  scripts     = scripts,
  helpers     = helpers,
  integrations = integrations,
  integration_flags = profile_module.get_integration_flags(user_profile),

  -- Icons
  icon_for = icon_for,

  -- State helpers
  state_module = state_module,

  -- Spaces
  refresh_spaces = space_fns.refresh_spaces,
  watch_spaces   = space_fns.watch_spaces,

  -- Window management
  yabai_available     = yabai_available,
  WINDOW_MANAGER_MODE = WINDOW_MANAGER_MODE,
  control_center_module = control_center_module,

  -- Appearance
  appearance = state.appearance,

  -- Specific scripts (consumed by items_left)
  FRONT_APP_ACTION_SCRIPT = SCRIPTS_DIR .. "/front_app_action.sh",
  YABAI_CONTROL_SCRIPT    = SCRIPTS_DIR .. "/yabai_control.sh",

  -- Widget factory (set below)
  widget_factory = nil,
}

-- Spaces init helper (used by items_left)
local function init_spaces()
  local yabai_bin = YABAI_BIN or "yabai"
  local wait_cmd = string.format(
    "path_to_yabai=%q; sketchybar_bin=%q; i=0; while [ $i -lt 10 ]; do " ..
      "\"$path_to_yabai\" -m query --spaces >/dev/null 2>&1 && break; " ..
      "sleep 0.2; i=$((i+1)); " ..
    "done; " ..
    "\"$sketchybar_bin\" --trigger space_change; " ..
    "\"$sketchybar_bin\" --trigger space_mode_refresh",
    yabai_bin, SKETCHYBAR_BIN
  )
  shell_utils.shell_exec(wait_cmd)
end

barista_context.init_spaces = init_spaces
barista_context.widget_factory = widgets_module.create_factory(sbar, theme, bc.settings, state, bc)

-----------------------------------------------------------------------
-- Begin configuration
-----------------------------------------------------------------------
sbar.begin_config()
shell_utils.sketchybar_cli(SKETCHYBAR_BIN, "--add event space_change >/dev/null 2>&1 || true")
shell_utils.sketchybar_cli(SKETCHYBAR_BIN, "--add event space_mode_refresh >/dev/null 2>&1 || true")

-- Global popup manager (invisible item that handles popup dismissal)
sbar.add("item", "popup_manager", {
  position = "left",
  drawing = false,
  script = POPUP_MANAGER_SCRIPT,
})

-- Bar configuration
sbar.bar(bc.bar)

-- Update external bar (yabai)
if yabai_available() then
  shell_utils.shell_exec(string.format("%s/update_external_bar.sh %d", SCRIPTS_DIR, bc.bar_height))
end

-- Defaults
sbar.default(bc.defaults)

-- Render All Menus (System, Workspace, Window)
local menu_metadata = menu_module.render_all_menus(barista_context) or {}

-- Register left and right bar items
-----------------------------------------------------------------------
-- Layout Processing
-----------------------------------------------------------------------
local function process_layout(layout, ctx)
  local sbar = ctx.sbar
  for _, entry in ipairs(layout) do
    if entry.type == "item" then
      sbar.add("item", entry.name, entry.props)
      if entry.attach_hover then
        ctx.attach_hover(entry.name)
      end
    elseif entry.type == "bracket" then
      sbar.add("bracket", entry.children or entry.name, entry.props)
    elseif entry.type == "set" then
      sbar.set(entry.name, entry.props)
    elseif entry.action == "exec" then
      ctx.shell_exec(entry.cmd)
    elseif entry.action == "call" then
      entry.fn()
    elseif entry.action == "subscribe_popup_autoclose" then
      ctx.subscribe_popup_autoclose(entry.name)
    elseif entry.action == "attach_hover" then
      ctx.attach_hover(entry.name)
    end
  end
end

local items_left  = require("items_left")
local items_right = require("items_right")

process_layout(items_left.get_layout(barista_context), barista_context)
process_layout(items_right.get_layout(barista_context), barista_context)

-- Write dynamic popup/submenu lists for C helpers (replaces hardcoded lists)
local submenu_registry = require("submenu_registry")
local popup_manager_items = {
  "front_app",
  "clock",
  "system_info",
  "volume",
  "battery",
  unpack(menu_metadata.popup_parents or {}),
}
if control_center_module then
  table.insert(popup_manager_items, "control_center")
end
submenu_registry.register(
  -- Popup parents (items with popup.drawing=toggle)
  popup_manager_items,
  -- Submenu sections (items inside menu popups that have their own popups)
  menu_metadata.submenu_parents or {}
)

shell_utils.shell_exec(string.format(
  "sleep %.1f; %s --subscribe popup_manager space_change display_changed display_added display_removed system_woke front_app_switched",
  POST_CONFIG_DELAY,
  SKETCHYBAR_BIN
))

-- End configuration
sbar.end_config()

print("main.lua finished loading!")
sbar.event_loop()
