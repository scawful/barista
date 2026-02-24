-- SketchyBar Configuration
-- Modular, modern macOS status bar with Yabai integration

local sbar = require("sketchybar")
local theme = require("theme")
local json = require("json")
local utf8 = require("utf8")

-- Load modules
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/integrations/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/?.lua"

local state_module = require("state")
local profile_module = require("profile")
local bar_config = require("bar_config")
local icons_module = require("icons")
local icon_manager = require("icon_manager")  -- Centralized icon management with multi-font support
local shortcuts = require("shortcuts")  -- Keyboard shortcut management
local widgets_module = require("widgets")
local menu_module = require("menu")
local yaze_module = require("yaze")
local oracle_module = require("oracle")
local emacs_module = require("emacs")

-- Initialize component switcher for C/Lua hybrid architecture
local component_switcher = require("component_switcher")

-- Lua-only mode: for environments without compiled helpers (no CMake) or when explicitly requested
local LUA_ONLY = (os.getenv("BARISTA_LUA_ONLY") == "1") or (os.getenv("BARISTA_NO_CMAKE") == "1")
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
component_switcher.set_mode(LUA_ONLY and "lua" or "auto")  -- Auto-select C when available, force Lua in fallback

if not LUA_ONLY and c_bridge then
  c_bridge.init()  -- Pre-cache common operations
else
  c_bridge = c_bridge or { init = function() end }
  print("Barista: running in Lua-only mode (no compiled helpers)")
end

-- Import existing icons into icon_manager for backwards compatibility
icon_manager.import_from_module(icons_module)

-- Paths (configurable via environment variables)
local PLUGIN_DIR = CONFIG_DIR .. "/plugins"
local EVENT_DIR = CONFIG_DIR .. "/helpers/event_providers"
local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function resolve_scripts_dir(state)
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end
  if state and type(state.paths) == "table" then
    local candidate = state.paths.scripts_dir or state.paths.scripts
    candidate = expand_path(candidate)
    if candidate and candidate ~= "" then
      local probe = io.open(candidate .. "/yabai_control.sh", "r")
      if probe then
        probe:close()
        return candidate
      end
    end
  end
  local config_scripts = CONFIG_DIR .. "/scripts"
  local probe = io.open(config_scripts .. "/yabai_control.sh", "r")
  if probe then
    probe:close()
    return config_scripts
  end
  local legacy_scripts = HOME .. "/.config/scripts"
  local legacy_probe = io.open(legacy_scripts .. "/yabai_control.sh", "r")
  if legacy_probe then
    legacy_probe:close()
    return legacy_scripts
  end
  return config_scripts
end

local function resolve_code_dir(state)
  local override = os.getenv("BARISTA_CODE_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end
  if state and type(state.paths) == "table" then
    local candidate = state.paths.code_dir or state.paths.code
    candidate = expand_path(candidate)
    if candidate and candidate ~= "" then
      return candidate
    end
  end
  return HOME .. "/src"
end

local function compiled_script(binary_name, fallback)
  if LUA_ONLY then
    return fallback
  end
  local path = string.format("%s/bin/%s", CONFIG_DIR, binary_name)
  local file = io.open(path, "r")
  if file then
    file:close()
    return path
  end
  print("WARNING: Binary not found: " .. path)
  return fallback
end

local function resolve_menu_action_script()
  local candidates = {
    CONFIG_DIR .. "/bin/menu_action",
    CONFIG_DIR .. "/helpers/menu_action",
    PLUGIN_DIR .. "/menu_action.sh",
  }
  for _, candidate in ipairs(candidates) do
    local file = io.open(candidate, "r")
    if file then
      file:close()
      return candidate
    end
  end
  return ""
end

local HOVER_SCRIPT = compiled_script("popup_hover", PLUGIN_DIR .. "/popup_hover.sh")
local POPUP_ANCHOR_SCRIPT = compiled_script("popup_anchor", PLUGIN_DIR .. "/popup_anchor.sh")
local SUBMENU_HOVER_SCRIPT = compiled_script("submenu_hover", PLUGIN_DIR .. "/submenu_hover.sh")
local POPUP_MANAGER_SCRIPT = compiled_script("popup_manager", PLUGIN_DIR .. "/popup_manager.sh")
local POPUP_GUARD_SCRIPT = compiled_script("popup_guard", PLUGIN_DIR .. "/popup_guard.sh")

-- Environment
local NET_INTERFACE = os.getenv("SKETCHYBAR_NET_INTERFACE") or "en0"

-- Load state and profile
local state = state_module.load()
local profile_name = profile_module.get_selected_profile(state)
local user_profile = profile_module.load(profile_name)

-- Merge profile configuration with state
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

local CODE_DIR = resolve_code_dir(state)

local SCRIPTS_DIR = resolve_scripts_dir(state)

-- Scripts
local YABAI_CONTROL_SCRIPT = SCRIPTS_DIR .. "/yabai_control.sh"
local SKHD_CONTROL_SCRIPT = SCRIPTS_DIR .. "/skhd_control.sh"
local FRONT_APP_ACTION_SCRIPT = SCRIPTS_DIR .. "/front_app_action.sh"

local function integration_enabled(name)
  local entry = state_module.get_integration(state, name)
  if type(entry) ~= "table" then
    return false
  end
  if entry.enabled == nil then
    return false
  end
  return entry.enabled ~= false
end

local yaze_enabled = integration_enabled("yaze")
local oracle_enabled = integration_enabled("oracle")
local emacs_enabled = integration_enabled("emacs")
local halext_enabled = integration_enabled("halext")
local halext_module = halext_enabled and require("halext") or nil
local cortex_enabled = integration_enabled("cortex")
local cortex_module = nil
if cortex_enabled then
  local ok, mod = pcall(require, "cortex")
  if ok then
    cortex_module = mod
  else
    print("Barista: cortex integration enabled but module not found")
  end
end

-- Control Center module (replaces/augments cortex widget)
local control_center_enabled = integration_enabled("control_center") or cortex_enabled
local control_center_module = nil
if control_center_enabled then
  local ok, mod = pcall(require, "control_center")
  if ok then
    control_center_module = mod
  else
    print("Barista: control_center module not found, falling back to cortex")
  end
end

local function resolve_sketchybar_bin()
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
    local file = io.open(candidate, "r")
    if file then
      file:close()
      return candidate
    end
  end
  return "sketchybar"
end

local SKETCHYBAR_BIN = resolve_sketchybar_bin()
local POST_CONFIG_DELAY = 1.0

local function resolve_yabai_bin()
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
    local file = io.open(candidate, "r")
    if file then
      file:close()
      return candidate
    end
  end
  return nil
end

local YABAI_BIN = resolve_yabai_bin()

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell_exec(cmd)
  local base_path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
  local env_path = os.getenv("PATH")
  if env_path and env_path ~= "" then
    base_path = base_path .. ":" .. env_path
  end
  sbar.exec(string.format("env PATH=%s bash -lc %s", shell_quote(base_path), shell_quote(cmd)))
end

local function sketchybar_cli(cmd)
  if not cmd or cmd == "" then
    return
  end
  shell_exec(string.format("%s %s", SKETCHYBAR_BIN, cmd))
end

local function open_path(path)
  return string.format("open %q", path)
end

local function open_url(url)
  return string.format("open %q", url)
end

local function call_script(script_path, ...)
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

local function file_exists(path)
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

local POPUP_TOGGLE_SCRIPT = SCRIPTS_DIR .. "/focus_display_and_toggle_popup.sh"
if not file_exists(POPUP_TOGGLE_SCRIPT) then
  local fallback_toggle_script = CONFIG_DIR .. "/scripts/focus_display_and_toggle_popup.sh"
  if file_exists(fallback_toggle_script) then
    POPUP_TOGGLE_SCRIPT = fallback_toggle_script
  end
end
local POPUP_TOGGLE_AVAILABLE = file_exists(POPUP_TOGGLE_SCRIPT)

local function popup_toggle_action(item_name)
  if POPUP_TOGGLE_AVAILABLE then
    return call_script(POPUP_TOGGLE_SCRIPT, item_name or "$NAME")
  end
  if item_name and item_name ~= "" then
    return string.format("%s --set %s popup.drawing=toggle", SKETCHYBAR_BIN, item_name)
  end
  return [[sketchybar -m --set $NAME popup.drawing=toggle]]
end

-- Cache yabai availability check (performance optimization)
local yabai_available_cache = nil
local function yabai_available()
  if yabai_available_cache == nil then
    if not YABAI_BIN or YABAI_BIN == "" then
      YABAI_BIN = resolve_yabai_bin()
    end
    yabai_available_cache = (YABAI_BIN ~= nil and YABAI_BIN ~= "")
  end
  return yabai_available_cache
end

local function normalize_window_manager_mode(mode)
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

local function resolve_window_manager_mode()
  local mode = os.getenv("BARISTA_WINDOW_MANAGER_MODE")
  if not mode or mode == "" then
    mode = state_module.get(state, "modes.window_manager", "auto")
  end
  return normalize_window_manager_mode(mode)
end

local WINDOW_MANAGER_MODE = resolve_window_manager_mode()

local function yabai_running()
  local handle = io.popen("pgrep -x yabai >/dev/null 2>&1 && echo 1 || echo 0")
  if not handle then
    return false
  end
  local result = handle:read("*a") or ""
  handle:close()
  return result:match("1") ~= nil
end

local function compute_window_manager_enabled()
  if WINDOW_MANAGER_MODE == "disabled" then
    return false
  end
  if WINDOW_MANAGER_MODE == "optional" then
    return yabai_running()
  end
  if WINDOW_MANAGER_MODE == "required" then
    if not yabai_available() then
      print("Barista: window_manager=required but yabai not found in PATH")
    end
    return yabai_available()
  end
  return yabai_available()
end

local WINDOW_MANAGER_ENABLED = compute_window_manager_enabled()

local function safe_icon(value)
  if type(value) ~= "string" then
    return nil
  end
  local ok = pcall(function()
    utf8.len(value)
  end)
  if ok then
    return value
  end
  return nil
end

local function icon_for(name, fallback)
  local from_state = safe_icon(state_module.get_icon(state, name, nil))
  if type(from_state) == "string" and from_state ~= "" then
    return from_state
  end
  local from_manager = safe_icon(icon_manager.get_char(name, nil))
  if type(from_manager) == "string" and from_manager ~= "" then
    return from_manager
  end
  local from_icons = safe_icon(icons_module.find(name))
  if type(from_icons) == "string" and from_icons ~= "" then
    return from_icons
  end
  return fallback or ""
end

_G.icon_for = icon_for

local function env_prefix(vars)
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

local function attach_hover(name)
  -- Hover script is now integrated into the widgets' own scripts for better performance
  -- Delay avoids "item not found" during initial config batch
  shell_exec(string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited", POST_CONFIG_DELAY, SKETCHYBAR_BIN, name))
end

local function subscribe_popup_autoclose(name)
  -- Delay avoids "item not found" during initial config batch
  local cmd = string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited mouse.exited.global", POST_CONFIG_DELAY, SKETCHYBAR_BIN, name)
  shell_exec(cmd)
end

-- Spaces management (display list, refresh, yabai signals)
local spaces_module = require("spaces")
local space_fns = spaces_module.create(CONFIG_DIR, PLUGIN_DIR, SKETCHYBAR_BIN, YABAI_BIN, shell_exec, yabai_available)
local associated_displays = space_fns.get_associated_displays()
print("Associated displays target: " .. associated_displays)
local refresh_spaces = space_fns.refresh_spaces
local watch_spaces = space_fns.watch_spaces

-- Bar appearance and defaults from bar_config module
local bc = bar_config.compute(state, theme, state_module, associated_displays)
local bar_height = bc.bar_height
local settings = bc.settings
local widget_height = bc.widget_height
local widget_corner_radius = bc.widget_corner_radius
local item_padding = bc.item_padding
local icon_padding = bc.icon_padding
local label_padding = bc.label_padding
local font_string = bc.font_string
local popup_background = bc.popup_background
local group_bg_color = bc.group_bg_color
local group_border_color = bc.group_border_color
local group_border_width = bc.group_border_width
local group_corner_radius = bc.group_corner_radius
local hover_color = bc.hover_color
local hover_border_color = bc.hover_border_color
local hover_border_width = bc.hover_border_width
local hover_animation_curve = bc.hover_animation_curve
local hover_animation_duration = bc.hover_animation_duration
local submenu_hover_color = bc.submenu_hover_color
local submenu_idle_color = bc.submenu_idle_color
local submenu_close_delay = bc.submenu_close_delay

-- Build shared context for menus/whichkey/popups
local profile_paths = profile_module.get_paths(user_profile)
local paths = {
  config_dir     = CONFIG_DIR,
  code_dir       = CODE_DIR,
  menu_data      = CONFIG_DIR .. "/data",
  workflow_data  = CONFIG_DIR .. "/data/workflow_shortcuts.json",
  rom_doc        = CODE_DIR .. "/docs/workflow/rom-hacking.org",
  yaze           = CODE_DIR .. "/yaze",
  afs           = CODE_DIR .. "/afs",
  cortex         = CODE_DIR .. "/cortex",
  halext_org     = CODE_DIR .. "/halext-org",
  halext_windows = CODE_DIR .. "/halext-org/docs/BACKGROUND_AGENTS.md",
  whichkey_plan  = CONFIG_DIR .. "/docs/features/WHICHKEY_PLAN.md",
  readme         = CONFIG_DIR .. "/README.md",
  sharing        = CONFIG_DIR .. "/docs/dev/SHARING.md",
  handoff        = CONFIG_DIR .. "/docs/guides/HANDOFF.md",
  apple_launcher = CONFIG_DIR .. "/bin/open_control_panel.sh",
}
-- Overlay profile-specific paths when provided
if profile_paths then
  for k, v in pairs(profile_paths) do
    paths[k] = v
  end
end

if yaze_module and type(yaze_module.configure) == "function" then
  yaze_module.configure({
    repo_path = paths.yaze,
    rom_workflow_doc = paths.rom_doc,
  })
end

local scripts = {
  menu_action        = resolve_menu_action_script(),
  set_appearance     = SCRIPTS_DIR .. "/set_appearance.sh",
  space_mode         = PLUGIN_DIR .. "/space_mode.sh",
  logs               = CONFIG_DIR .. "/plugins/bar_logs.sh",
  yabai_control      = YABAI_CONTROL_SCRIPT,
  accessibility      = SCRIPTS_DIR .. "/yabai_accessibility_fix.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh",
  halext_menu        = CONFIG_DIR .. "/plugins/halext_menu.sh",
  ssh_sync           = CONFIG_DIR .. "/helpers/ssh_sync.sh",
  cpp_project_switch = CONFIG_DIR .. "/helpers/cpp_project_switch.sh",
}

local helpers = {
  help_center = CONFIG_DIR .. "/gui/bin/help_center",
}

local integrations = {
  yaze   = yaze_enabled   and yaze_module   or nil,
  oracle = oracle_enabled and oracle_module or nil,
  emacs  = emacs_enabled  and emacs_module  or nil,
  halext = halext_enabled and halext_module or nil,
  cortex = cortex_module,
  control_center = control_center_module,
}

local hover_env = env_prefix({
  POPUP_HOVER_COLOR = tostring(hover_color),
  POPUP_HOVER_BORDER_COLOR = tostring(hover_border_color),
  POPUP_HOVER_BORDER_WIDTH = tostring(hover_border_width),
  POPUP_HOVER_ANIMATION_CURVE = tostring(hover_animation_curve),
  POPUP_HOVER_ANIMATION_DURATION = tostring(hover_animation_duration),
})
local hover_script_cmd = hover_env .. HOVER_SCRIPT

local submenu_env = env_prefix({
  SUBMENU_HOVER_BG = tostring(submenu_hover_color),
  SUBMENU_IDLE_BG = tostring(submenu_idle_color),
  SUBMENU_CLOSE_DELAY = tostring(submenu_close_delay),
  SUBMENU_ANIMATION_CURVE = tostring(hover_animation_curve),
  SUBMENU_ANIMATION_DURATION = tostring(hover_animation_duration),
})
local submenu_hover_script_cmd = submenu_env .. SUBMENU_HOVER_SCRIPT

local menu_context = {
  sbar = sbar,
  theme = theme,
  settings = settings,
  widget_height = widget_height,
  attach_hover = attach_hover,
  subscribe_popup_autoclose = subscribe_popup_autoclose,
  shell_exec = shell_exec,
  call_script = call_script,
  open_path = open_path,
  open_url = open_url,
  icon_for = icon_for,
  associated_displays = associated_displays,
  sketchybar_bin = SKETCHYBAR_BIN,
  post_config_delay = POST_CONFIG_DELAY,
  appearance = state.appearance,
  paths = paths,
  scripts = scripts,
  helpers = helpers,
  HOVER_SCRIPT = hover_script_cmd,
  SUBMENU_HOVER_SCRIPT = submenu_hover_script_cmd,
  popup_toggle_action = popup_toggle_action,
  popup_toggle_script = POPUP_TOGGLE_AVAILABLE and POPUP_TOGGLE_SCRIPT or nil,
  integration_flags = profile_module.get_integration_flags(user_profile),
  integrations = integrations,
}

-- Begin configuration
sbar.begin_config()
sketchybar_cli("--add event space_change >/dev/null 2>&1 || true")
sketchybar_cli("--add event space_mode_refresh >/dev/null 2>&1 || true")

-- Global popup manager (invisible item that handles popup dismissal)
sbar.add("item", "popup_manager", {
  position = "left",
  drawing = false,
  script = POPUP_MANAGER_SCRIPT,
})
-- OPTIMIZED: Reduced delay from 0.3s; small delay avoids startup "item not found" noise
shell_exec(string.format("sleep %.1f; %s --subscribe popup_manager space_change display_changed display_added display_removed system_woke front_app_switched", POST_CONFIG_DELAY, SKETCHYBAR_BIN))

-- Bar configuration
sbar.bar(bc.bar)

-- Update external bar (yabai)
local function update_external_bar()
  local script = string.format("%s/update_external_bar.sh %d", SCRIPTS_DIR, bar_height)
  shell_exec(script)
end
if yabai_available() then
  update_external_bar()
end

-- Defaults
sbar.default(bc.defaults)

-- Render All Menus (System, Workspace, Window)
menu_module.render_all_menus(menu_context)

-- Spaces init (used by items_left)
local function init_spaces()
  local yabai_bin = YABAI_BIN or "yabai"
  local wait_cmd = string.format(
    "path_to_yabai=%q; sketchybar_bin=%q; i=0; while [ $i -lt 10 ]; do " ..
      "\"$path_to_yabai\" -m query --spaces >/dev/null 2>&1 && break; " ..
      "sleep 0.2; i=$((i+1)); " ..
    "done; " ..
    "\"$sketchybar_bin\" --trigger space_change; " ..
    "\"$sketchybar_bin\" --trigger space_mode_refresh",
    yabai_bin,
    SKETCHYBAR_BIN
  )
  shell_exec(wait_cmd)
end

local widget_factory = widgets_module.create_factory(sbar, theme, settings, state)

local items_left = require("items_left")
local items_right = require("items_right")

local item_ctx = {
  sbar = sbar,
  theme = theme,
  settings = settings,
  font_string = font_string,
  PLUGIN_DIR = PLUGIN_DIR,
  CONFIG_DIR = CONFIG_DIR,
  widget_corner_radius = widget_corner_radius,
  widget_height = widget_height,
  popup_background = popup_background,
  hover_script_cmd = hover_script_cmd,
  popup_toggle_action = popup_toggle_action,
  attach_hover = attach_hover,
  subscribe_popup_autoclose = subscribe_popup_autoclose,
  shell_exec = shell_exec,
  SKETCHYBAR_BIN = SKETCHYBAR_BIN,
  POST_CONFIG_DELAY = POST_CONFIG_DELAY,
  associated_displays = associated_displays,
  call_script = call_script,
  FRONT_APP_ACTION_SCRIPT = FRONT_APP_ACTION_SCRIPT,
  YABAI_CONTROL_SCRIPT = YABAI_CONTROL_SCRIPT,
  refresh_spaces = refresh_spaces,
  watch_spaces = watch_spaces,
  init_spaces = init_spaces,
  yabai_available = yabai_available,
  control_center_module = control_center_module,
  state = state,
  WINDOW_MANAGER_MODE = WINDOW_MANAGER_MODE,
  group_bg_color = group_bg_color,
  group_border_color = group_border_color,
  group_border_width = group_border_width,
  group_corner_radius = group_corner_radius,
  widget_factory = widget_factory,
  icon_for = icon_for,
  state_module = state_module,
  env_prefix = env_prefix,
  compiled_script = compiled_script,
  hover_color = hover_color,
  hover_animation_curve = hover_animation_curve,
  hover_animation_duration = hover_animation_duration,
  open_path = open_path,
  CODE_DIR = CODE_DIR,
}

items_left.register(item_ctx)
items_right.register(item_ctx)

-- End configuration
sbar.end_config()

print("main.lua finished loading!")
sbar.event_loop()
